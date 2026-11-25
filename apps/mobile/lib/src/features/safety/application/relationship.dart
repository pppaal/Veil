/// Who an account is to this phone, from facts a stranger cannot create in
/// minutes (ContactTrust.relationshipAt). Checked in the order
/// changed, verified, saved, known, new.
///
/// - [changed]: an identity change of theirs waits for review, or a new
///   device of theirs was admitted in the 7 days before.
/// - [verified]: every pinned device of theirs was verified and nothing
///   about them is pending.
/// - [saved]: a nickname names them, saved at least 7 days before (or
///   before this phone kept trust records).
/// - [known]: a 1:1 with them accepted at least 7 days before, holding a
///   text or file this phone sent; for a group sender, that 1:1, a group I
///   created, or a group accepted at least 7 days before.
/// - [newContact]: anyone else.
enum Relationship { verified, saved, known, newContact, changed }
