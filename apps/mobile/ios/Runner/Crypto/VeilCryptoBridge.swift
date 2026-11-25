import CommonCrypto
import Flutter
import Foundation
import Security

#if canImport(LibSignalClient)
import LibSignalClient
#endif

// `io.veil.crypto/bridge` handler — iOS counterpart of
// android/.../crypto/VeilCryptoBridge.kt. Implements the channel contract in
// docs/crypto-mobile-bridge-design.md on top of LibSignalClient (Swift
// Package: https://github.com/signalapp/libsignal, product `LibSignalClient`,
// pinned to the same tag as libsignal-android in build.gradle.kts).
//
// The file compiles with or without the package: when `LibSignalClient` is
// not linked, every method answers `bridgeUnavailable`, so a build that has
// not added the SPM dependency yet fails closed instead of silently falling
// back to anything else. Add the package in Xcode: File ▸ Add Package
// Dependencies… ▸ `https://github.com/signalapp/libsignal` ▸ exact version
// (see docs/libsignal-migration-implementation.md §2) ▸ link `LibSignalClient`
// to the Runner target.
//
// Rules, same as Android: private keys and session records never cross the
// channel; every failure is a FlutterError with a stable code; nothing is
// logged. API names target LibSignalClient 0.86.x — VERIFY against the
// pinned tag before the first build.

final class VeilCryptoBridgePlugin: NSObject, FlutterPlugin {
  static let channelName = "io.veil.crypto/bridge"

  static func register(with registrar: FlutterPluginRegistrar) {
    let channel = FlutterMethodChannel(name: channelName, binaryMessenger: registrar.messenger())
    let instance = VeilCryptoBridgePlugin()
    registrar.addMethodCallDelegate(instance, channel: channel)
  }

  #if canImport(LibSignalClient)
  private let bridge = VeilCryptoBridge()
  #endif

  func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    #if canImport(LibSignalClient)
    bridge.handle(call, result)
    #else
    result(FlutterError(code: "bridgeUnavailable", message: "LibSignalClient is not linked", details: nil))
    #endif
  }
}

#if canImport(LibSignalClient)

final class VeilCryptoBridge {
  /// Opaque handle Dart stores as `identityPrivateKeyRef`. Carries no key material.
  private static let identityRef = "veil-libsignal-identity-v1"
  /// VEIL device ids are already per-device UUIDs; every ProtocolAddress uses sub-device 1.
  private static let libsignalDeviceId: UInt32 = 1
  private static let attachmentWrapInfo = Array("veil-attachment-wrap-v1".utf8)
  /// libsignal-serialized EC public key length (type byte + 32).
  private static let ecPublicLength = 33

  private let store = KeychainSignalStore()
  private let context = NullContext()

  enum BridgeError: Error {
    case argument(String)
    case bundle(String)
    case identityRef
    case unsupportedMessageType
  }

  func handle(_ call: FlutterMethodCall, _ result: @escaping FlutterResult) {
    do {
      switch call.method {
      case "generateDeviceIdentity": result(try generateDeviceIdentity(call))
      case "extractIdentityPublicKey": result(try extractIdentityPublicKey(call))
      case "bootstrapSession": result(try bootstrapSession(call))
      case "encryptMessage": result(try encryptMessage(call))
      case "decryptMessage": result(try decryptMessage(call))
      case "encryptAttachmentKey": result(try encryptAttachmentKey(call))
      case "decryptAttachmentKey": result(try decryptAttachmentKey(call))
      case "hasSession": result(["present": try hasSession(call)])
      case "wipeCryptoState": result(["wiped": try wipe(call)])
      default: result(FlutterMethodNotImplemented)
      }
    } catch SignalError.sessionNotFound {
      result(FlutterError(code: "sessionNotFound", message: nil, details: nil))
    } catch SignalError.untrustedIdentity {
      result(FlutterError(code: "identityMismatch", message: nil, details: nil))
    } catch BridgeError.bundle(let why) {
      result(FlutterError(code: "bundleInvalid", message: why, details: nil))
    } catch BridgeError.argument(let field) {
      result(FlutterError(code: "invalidArgument", message: field, details: nil))
    } catch BridgeError.identityRef, KeychainSignalStore.StoreError.missingIdentity {
      result(FlutterError(code: "keyWipeRequired", message: nil, details: nil))
    } catch {
      result(FlutterError(code: "decryptFailed", message: String(describing: type(of: error)), details: nil))
    }
  }

  // MARK: identity

  private func generateDeviceIdentity(_ call: FlutterMethodCall) throws -> [String: Any] {
    _ = try requireString(call, "deviceId")
    try store.wipeAll()

    let identity = IdentityKeyPair.generate()
    let registrationId = UInt32.random(in: 1...16380)
    try store.installIdentity(identity, registrationId: registrationId)

    let now = UInt64(Date().timeIntervalSince1970 * 1000)

    let signedPreKeyId = UInt32.random(in: 1...0xFFFFFF)
    let signedPrivate = PrivateKey.generate()
    let signedSig = identity.privateKey.generateSignature(message: signedPrivate.publicKey.serialize())
    try store.storeSignedPreKey(
      SignedPreKeyRecord(id: signedPreKeyId, timestamp: now, privateKey: signedPrivate, signature: signedSig),
      id: signedPreKeyId, context: context)

    let kyberPreKeyId = UInt32.random(in: 1...0xFFFFFF)
    let kyberPair = KEMKeyPair.generate()
    let kyberSig = identity.privateKey.generateSignature(message: kyberPair.publicKey.serialize())
    try store.storeKyberPreKey(
      KyberPreKeyRecord(id: kyberPreKeyId, timestamp: now, keyPair: kyberPair, signature: kyberSig),
      id: kyberPreKeyId, context: context)

    let preKeyId = UInt32.random(in: 1...0xFFFFFF)
    let prePrivate = PrivateKey.generate()
    try store.storePreKey(PreKeyRecord(id: preKeyId, privateKey: prePrivate), id: preKeyId, context: context)

    let bundle: [String: Any] = [
      "v": 2,
      "registrationId": registrationId,
      "deviceId": Self.libsignalDeviceId,
      "signedPreKeyId": signedPreKeyId,
      "signedPreKey": b64(signedPrivate.publicKey.serialize()),
      "signedPreKeySignature": b64(signedSig),
      "kyberPreKeyId": kyberPreKeyId,
      "kyberPreKey": b64(kyberPair.publicKey.serialize()),
      "kyberPreKeySignature": b64(kyberSig),
      "preKeyId": preKeyId,
      "preKey": b64(prePrivate.publicKey.serialize()),
    ]
    let bundleJson = try JSONSerialization.data(withJSONObject: bundle, options: [.sortedKeys])
    return [
      "identityPublicKey": b64(identity.identityKey.serialize()),
      "identityPrivateKeyRef": Self.identityRef,
      "signedPrekeyBundle": b64([UInt8](bundleJson)),
    ]
  }

  private func extractIdentityPublicKey(_ call: FlutterMethodCall) throws -> [String: Any] {
    try requireIdentityRef(call)
    return ["identityPublicKey": b64(try store.identityKeyPair(context: context).identityKey.serialize())]
  }

  // MARK: sessions

  private func bootstrapSession(_ call: FlutterMethodCall) throws -> [String: Any] {
    let remoteDeviceId = try requireString(call, "remoteDeviceId")
    let remoteIdentity = try parseIdentity(try requireString(call, "remoteIdentityPublicKey"))
    let bundle = try parseBundle(try requireString(call, "remoteSignedPrekeyBundle"), identity: remoteIdentity)
    let address = try ProtocolAddress(name: remoteDeviceId, deviceId: Self.libsignalDeviceId)
    // VERIFY(0.86.5): processPreKeyBundle(_:for:sessionStore:identityStore:now:context:)
    try processPreKeyBundle(
      bundle, for: address, sessionStore: store, identityStore: store, now: Date(), context: context)
    return ["remoteIdentityFingerprint": fingerprint(remoteIdentity.serialize())]
  }

  private func hasSession(_ call: FlutterMethodCall) throws -> Bool {
    guard let remoteDeviceId = (call.arguments as? [String: Any])?["remoteDeviceId"] as? String else { return false }
    let address = try ProtocolAddress(name: remoteDeviceId, deviceId: Self.libsignalDeviceId)
    return try store.loadSession(for: address, context: context) != nil
  }

  // MARK: messages

  private func encryptMessage(_ call: FlutterMethodCall) throws -> [String: Any] {
    let remoteDeviceId = try requireString(call, "remoteDeviceId")
    var plaintext = try unb64(try requireString(call, "plaintext"))
    defer { zero(&plaintext) }
    let address = try ProtocolAddress(name: remoteDeviceId, deviceId: Self.libsignalDeviceId)
    // VERIFY(0.86.5): signalEncrypt(message:for:sessionStore:identityStore:now:context:)
    let message = try signalEncrypt(
      message: plaintext, for: address, sessionStore: store, identityStore: store, now: Date(), context: context)
    let type: Int
    switch message.messageType {
    case .preKey: type = 3
    case .whisper: type = 2
    default: throw BridgeError.unsupportedMessageType
    }
    return ["ciphertext": b64(message.serialize()), "messageType": type]
  }

  private func decryptMessage(_ call: FlutterMethodCall) throws -> [String: Any] {
    let senderDeviceId = try requireString(call, "senderDeviceId")
    let ciphertext = try unb64(try requireString(call, "ciphertext"))
    guard let messageType = (call.arguments as? [String: Any])?["messageType"] as? Int else {
      throw BridgeError.argument("messageType")
    }
    let address = try ProtocolAddress(name: senderDeviceId, deviceId: Self.libsignalDeviceId)
    var plaintext: [UInt8]
    switch messageType {
    case 3:
      // VERIFY(0.86.5): signalDecryptPreKey(message:from:sessionStore:identityStore:preKeyStore:
      //   signedPreKeyStore:kyberPreKeyStore:context:usePqRatchet:)
      plaintext = try signalDecryptPreKey(
        message: try PreKeySignalMessage(bytes: ciphertext), from: address,
        sessionStore: store, identityStore: store, preKeyStore: store,
        signedPreKeyStore: store, kyberPreKeyStore: store, context: context, usePqRatchet: .yes)
    case 2:
      plaintext = try signalDecrypt(
        message: try SignalMessage(bytes: ciphertext), from: address,
        sessionStore: store, identityStore: store, context: context)
    default:
      throw BridgeError.unsupportedMessageType
    }
    defer { zero(&plaintext) }
    return ["plaintext": b64(plaintext)]
  }

  // MARK: attachment key wrap
  //
  // ephemeral X25519 → HKDF-SHA256(salt = ephPub, info = "veil-attachment-wrap-v1")
  // → AES-256-GCM. wrappedKey = ephPub(33) || ct || tag(16). Byte-compatible with
  // the Android bridge and the lib adapter so attachments interoperate.

  private func encryptAttachmentKey(_ call: FlutterMethodCall) throws -> [String: Any] {
    let recipientIdentity = try parseIdentity(try requireString(call, "recipientIdentityPublicKey"))
    let json = try parseBundleJson(try requireString(call, "recipientSignedPrekeyBundle"))
    guard let spkB64 = json["signedPreKey"] as? String, let sigB64 = json["signedPreKeySignature"] as? String else {
      throw BridgeError.bundle("signed prekey missing")
    }
    let signedPreKey = try PublicKey(try unb64(spkB64))
    guard try recipientIdentity.publicKey.verifySignature(message: signedPreKey.serialize(), signature: try unb64(sigB64)) else {
      throw BridgeError.bundle("signed prekey signature invalid")
    }
    var attachmentKey = try unb64(try requireString(call, "attachmentKey"))
    defer { zero(&attachmentKey) }
    guard attachmentKey.count == 32 else { throw BridgeError.argument("attachmentKey") }

    let eph = PrivateKey.generate()
    var shared = eph.keyAgreement(with: signedPreKey)
    defer { zero(&shared) }
    var wrapKey = try hkdf(outputLength: 32, inputKeyMaterial: shared, salt: eph.publicKey.serialize(), info: Self.attachmentWrapInfo)
    defer { zero(&wrapKey) }
    var nonce = [UInt8](repeating: 0, count: 12)
    guard SecRandomCopyBytes(kSecRandomDefault, nonce.count, &nonce) == errSecSuccess else {
      throw BridgeError.argument("rng")
    }
    // VERIFY(0.86.5): Aes256GcmEncryption(key:nonce:associatedData:)
    let gcm = try Aes256GcmEncryption(key: wrapKey, nonce: nonce, associatedData: [])
    var sealed = attachmentKey
    try gcm.encrypt(&sealed)
    let tag = try gcm.computeTag()
    return [
      "wrappedKey": b64(eph.publicKey.serialize() + sealed + tag),
      "wrapNonce": b64(nonce),
    ]
  }

  private func decryptAttachmentKey(_ call: FlutterMethodCall) throws -> [String: Any] {
    try requireIdentityRef(call)
    let wrapped = try unb64(try requireString(call, "wrappedKey"))
    let nonce = try unb64(try requireString(call, "wrapNonce"))
    guard wrapped.count >= Self.ecPublicLength + 16, nonce.count == 12 else { throw BridgeError.argument("wrappedKey") }
    let ephPub = try PublicKey(Array(wrapped[0..<Self.ecPublicLength]))
    let body = Array(wrapped[Self.ecPublicLength..<(wrapped.count - 16)])
    let tag = Array(wrapped[(wrapped.count - 16)...])

    var lastError: Error = BridgeError.argument("wrappedKey")
    for record in try store.allSignedPreKeys().sorted(by: { $0.timestamp > $1.timestamp }) {
      do {
        var shared = try record.privateKey.keyAgreement(with: ephPub)
        defer { zero(&shared) }
        var wrapKey = try hkdf(outputLength: 32, inputKeyMaterial: shared, salt: ephPub.serialize(), info: Self.attachmentWrapInfo)
        defer { zero(&wrapKey) }
        let gcm = try Aes256GcmDecryption(key: wrapKey, nonce: nonce, associatedData: [])
        var key = body
        try gcm.decrypt(&key)
        guard try gcm.verifyTag(tag) else { throw BridgeError.argument("tag") }
        defer { zero(&key) }
        return ["attachmentKey": b64(key)]
      } catch {
        lastError = error
      }
    }
    throw lastError
  }

  // MARK: wipe

  private func wipe(_ call: FlutterMethodCall) throws -> Bool {
    let scope = try requireString(call, "scope")
    if scope == "all" {
      try store.wipeAll()
    } else {
      let peer = (call.arguments as? [String: Any])?["remoteDeviceId"] as? String ?? scope
      try store.wipeConversation(peerDeviceId: peer)
    }
    return true
  }

  // MARK: bundle parsing

  private func parseBundleJson(_ encoded: String) throws -> [String: Any] {
    guard let obj = try? JSONSerialization.jsonObject(with: Data(try unb64(encoded))) as? [String: Any] else {
      throw BridgeError.bundle("malformed bundle")
    }
    return obj
  }

  private func parseBundle(_ encoded: String, identity: IdentityKey) throws -> PreKeyBundle {
    let json = try parseBundleJson(encoded)
    guard (json["v"] as? Int) == 2 else { throw BridgeError.bundle("unsupported bundle version") }
    do {
      guard
        let registrationId = json["registrationId"] as? UInt32,
        let signedPreKeyId = json["signedPreKeyId"] as? UInt32,
        let signedPreKeyB64 = json["signedPreKey"] as? String,
        let signedSigB64 = json["signedPreKeySignature"] as? String,
        let kyberPreKeyId = json["kyberPreKeyId"] as? UInt32,
        let kyberPreKeyB64 = json["kyberPreKey"] as? String,
        let kyberSigB64 = json["kyberPreKeySignature"] as? String
      else { throw BridgeError.bundle("bundle fields missing") }
      let deviceId = json["deviceId"] as? UInt32 ?? Self.libsignalDeviceId
      let signedPreKey = try PublicKey(try unb64(signedPreKeyB64))
      let kyberPreKey = try KEMPublicKey(try unb64(kyberPreKeyB64))
      // VERIFY(0.86.5): PreKeyBundle initializers with/without one-time prekey.
      if let preKeyId = json["preKeyId"] as? UInt32, let preKeyB64 = json["preKey"] as? String {
        return try PreKeyBundle(
          registrationId: registrationId, deviceId: deviceId,
          prekeyId: preKeyId, prekey: try PublicKey(try unb64(preKeyB64)),
          signedPrekeyId: signedPreKeyId, signedPrekey: signedPreKey, signedPrekeySignature: try unb64(signedSigB64),
          identity: identity,
          kyberPrekeyId: kyberPreKeyId, kyberPrekey: kyberPreKey, kyberPrekeySignature: try unb64(kyberSigB64))
      }
      return try PreKeyBundle(
        registrationId: registrationId, deviceId: deviceId,
        signedPrekeyId: signedPreKeyId, signedPrekey: signedPreKey, signedPrekeySignature: try unb64(signedSigB64),
        identity: identity,
        kyberPrekeyId: kyberPreKeyId, kyberPrekey: kyberPreKey, kyberPrekeySignature: try unb64(kyberSigB64))
    } catch let e as BridgeError {
      throw e
    } catch {
      throw BridgeError.bundle("bundle fields invalid")
    }
  }

  private func parseIdentity(_ encoded: String) throws -> IdentityKey {
    do { return try IdentityKey(bytes: try unb64(encoded)) } catch { throw BridgeError.bundle("identity key invalid") }
  }

  // MARK: helpers

  private func fingerprint(_ identitySerialized: [UInt8]) -> String {
    // SHA-256 truncated to 16 bytes, same as the Android bridge / lib adapter.
    var digest = [UInt8](repeating: 0, count: 32)
    identitySerialized.withUnsafeBufferPointer { buf in
      _ = CC_SHA256(buf.baseAddress, CC_LONG(buf.count), &digest)
    }
    return b64(Array(digest[0..<16]))
  }

  private func requireString(_ call: FlutterMethodCall, _ key: String) throws -> String {
    guard let value = (call.arguments as? [String: Any])?[key] as? String, !value.isEmpty else {
      throw BridgeError.argument(key)
    }
    return value
  }

  private func requireIdentityRef(_ call: FlutterMethodCall) throws {
    guard try requireString(call, "identityPrivateKeyRef") == Self.identityRef, store.hasIdentity() else {
      throw BridgeError.identityRef
    }
  }

  private func b64(_ bytes: [UInt8]) -> String {
    Data(bytes).base64EncodedString()
      .replacingOccurrences(of: "+", with: "-")
      .replacingOccurrences(of: "/", with: "_")
      .replacingOccurrences(of: "=", with: "")
  }

  private func unb64(_ value: String) throws -> [UInt8] {
    var s = value.replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
    while s.count % 4 != 0 { s.append("=") }
    guard let data = Data(base64Encoded: s) else { throw BridgeError.argument("base64") }
    return [UInt8](data)
  }

  private func zero(_ bytes: inout [UInt8]) {
    for i in bytes.indices { bytes[i] = 0 }
  }
}

// MARK: - Keychain-backed stores

/// Every libsignal store protocol, persisted in the Keychain
/// (`kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly`, never synced to
/// iCloud). Records are serialized on every write because libsignal mutates
/// sessions on each encrypt/decrypt.
///
/// VERIFY(0.86.5): protocol requirements of IdentityKeyStore / PreKeyStore /
/// SignedPreKeyStore / KyberPreKeyStore / SessionStore.
final class KeychainSignalStore: IdentityKeyStore, PreKeyStore, SignedPreKeyStore, KyberPreKeyStore, SessionStore {
  enum StoreError: Error { case missingIdentity, keychain(OSStatus) }

  private let service = "io.veil.mobile.libsignal"

  // MARK: identity

  func hasIdentity() -> Bool { (try? read("identity/pair")) != nil }

  func installIdentity(_ pair: IdentityKeyPair, registrationId: UInt32) throws {
    try write("identity/pair", pair.serialize())
    try write("identity/registration", Array(String(registrationId).utf8))
  }

  func identityKeyPair(context: StoreContext) throws -> IdentityKeyPair {
    guard let bytes = try read("identity/pair") else { throw StoreError.missingIdentity }
    return try IdentityKeyPair(bytes: bytes)
  }

  func localRegistrationId(context: StoreContext) throws -> UInt32 {
    guard let bytes = try read("identity/registration"), let value = UInt32(String(decoding: bytes, as: UTF8.self)) else {
      throw StoreError.missingIdentity
    }
    return value
  }

  func saveIdentity(_ identity: IdentityKey, for address: ProtocolAddress, context: StoreContext) throws -> IdentityChange {
    let key = "trusted/\(address.name)/\(address.deviceId)"
    let existing = try read(key)
    try write(key, identity.serialize())
    if let existing, existing != identity.serialize() { return .replacedExisting }
    return .newOrUnchanged
  }

  /// Trust-on-first-use, then pin; a rotated key surfaces as `identityMismatch`.
  func isTrustedIdentity(_ identity: IdentityKey, for address: ProtocolAddress, direction: Direction, context: StoreContext) throws -> Bool {
    guard let existing = try read("trusted/\(address.name)/\(address.deviceId)") else { return true }
    return existing == identity.serialize()
  }

  func identity(for address: ProtocolAddress, context: StoreContext) throws -> IdentityKey? {
    guard let bytes = try read("trusted/\(address.name)/\(address.deviceId)") else { return nil }
    return try IdentityKey(bytes: bytes)
  }

  // MARK: prekeys

  func loadPreKey(id: UInt32, context: StoreContext) throws -> PreKeyRecord {
    guard let bytes = try read("prekey/\(id)") else { throw SignalError.invalidKeyIdentifier("no prekey \(id)") }
    return try PreKeyRecord(bytes: bytes)
  }

  func storePreKey(_ record: PreKeyRecord, id: UInt32, context: StoreContext) throws {
    try write("prekey/\(id)", record.serialize())
  }

  func removePreKey(id: UInt32, context: StoreContext) throws { try delete("prekey/\(id)") }

  func loadSignedPreKey(id: UInt32, context: StoreContext) throws -> SignedPreKeyRecord {
    guard let bytes = try read("signed-prekey/\(id)") else { throw SignalError.invalidKeyIdentifier("no signed prekey \(id)") }
    return try SignedPreKeyRecord(bytes: bytes)
  }

  func storeSignedPreKey(_ record: SignedPreKeyRecord, id: UInt32, context: StoreContext) throws {
    try write("signed-prekey/\(id)", record.serialize())
  }

  func allSignedPreKeys() throws -> [SignedPreKeyRecord] {
    try keys(prefix: "signed-prekey/").compactMap { try read($0) }.map { try SignedPreKeyRecord(bytes: $0) }
  }

  func loadKyberPreKey(id: UInt32, context: StoreContext) throws -> KyberPreKeyRecord {
    guard let bytes = try read("kyber-prekey/\(id)") else { throw SignalError.invalidKeyIdentifier("no kyber prekey \(id)") }
    return try KyberPreKeyRecord(bytes: bytes)
  }

  func storeKyberPreKey(_ record: KyberPreKeyRecord, id: UInt32, context: StoreContext) throws {
    try write("kyber-prekey/\(id)", record.serialize())
  }

  /// Last-resort Kyber prekey stays usable; only record the use.
  func markKyberPreKeyUsed(id: UInt32, context: StoreContext) throws {
    try write("kyber-prekey-used/\(id)", [1])
  }

  // MARK: sessions

  func loadSession(for address: ProtocolAddress, context: StoreContext) throws -> SessionRecord? {
    guard let bytes = try read("session/\(address.name)/\(address.deviceId)") else { return nil }
    return try SessionRecord(bytes: bytes)
  }

  func loadExistingSessions(for addresses: [ProtocolAddress], context: StoreContext) throws -> [SessionRecord] {
    try addresses.map { address in
      guard let record = try loadSession(for: address, context: context) else { throw SignalError.sessionNotFound("\(address)") }
      return record
    }
  }

  func storeSession(_ record: SessionRecord, for address: ProtocolAddress, context: StoreContext) throws {
    try write("session/\(address.name)/\(address.deviceId)", record.serialize())
  }

  // MARK: wipe

  func wipeConversation(peerDeviceId: String) throws {
    for key in try keys(prefix: "session/\(peerDeviceId)/") { try delete(key) }
    for key in try keys(prefix: "trusted/\(peerDeviceId)/") { try delete(key) }
  }

  func wipeAll() throws {
    let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service]
    let status = SecItemDelete(query as CFDictionary)
    guard status == errSecSuccess || status == errSecItemNotFound else { throw StoreError.keychain(status) }
  }

  // MARK: keychain primitives

  private func baseQuery(_ account: String) -> [String: Any] {
    [
      kSecClass as String: kSecClassGenericPassword,
      kSecAttrService as String: service,
      kSecAttrAccount as String: account,
    ]
  }

  private func read(_ account: String) throws -> [UInt8]? {
    var query = baseQuery(account)
    query[kSecReturnData as String] = true
    query[kSecMatchLimit as String] = kSecMatchLimitOne
    var item: CFTypeRef?
    let status = SecItemCopyMatching(query as CFDictionary, &item)
    if status == errSecItemNotFound { return nil }
    guard status == errSecSuccess, let data = item as? Data else { throw StoreError.keychain(status) }
    return [UInt8](data)
  }

  private func write(_ account: String, _ bytes: [UInt8]) throws {
    let data = Data(bytes)
    let update: [String: Any] = [kSecValueData as String: data]
    let status = SecItemUpdate(baseQuery(account) as CFDictionary, update as CFDictionary)
    if status == errSecSuccess { return }
    guard status == errSecItemNotFound else { throw StoreError.keychain(status) }
    var add = baseQuery(account)
    add[kSecValueData as String] = data
    add[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
    let addStatus = SecItemAdd(add as CFDictionary, nil)
    guard addStatus == errSecSuccess else { throw StoreError.keychain(addStatus) }
  }

  private func delete(_ account: String) throws {
    let status = SecItemDelete(baseQuery(account) as CFDictionary)
    guard status == errSecSuccess || status == errSecItemNotFound else { throw StoreError.keychain(status) }
  }

  private func keys(prefix: String) throws -> [String] {
    var query: [String: Any] = [
      kSecClass as String: kSecClassGenericPassword,
      kSecAttrService as String: service,
      kSecReturnAttributes as String: true,
      kSecMatchLimit as String: kSecMatchLimitAll,
    ]
    var items: CFTypeRef?
    let status = SecItemCopyMatching(query as CFDictionary, &items)
    if status == errSecItemNotFound { return [] }
    guard status == errSecSuccess, let array = items as? [[String: Any]] else { throw StoreError.keychain(status) }
    query.removeAll()
    return array.compactMap { $0[kSecAttrAccount as String] as? String }.filter { $0.hasPrefix(prefix) }
  }
}

#endif
