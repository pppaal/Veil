-- The device a completed transfer created. DeviceTransferService.complete
-- writes it in the transaction that creates the device and revokes the old
-- one, so a retry of the same completion (its first response lost on the
-- network) is answered with the same device instead of
-- transfer_session_inactive, which left the user with no device at all.
ALTER TABLE "device_transfer_sessions" ADD COLUMN "new_device_id" UUID;
