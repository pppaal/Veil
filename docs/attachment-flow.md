# Attachment Flow

## Send path

1. Sender encrypts the file locally with a content key.
2. Sender asks the API for an upload ticket.
3. API creates attachment metadata and returns storage coordinates.
4. Sender uploads only the encrypted blob to S3-compatible storage.
5. Sender sends a message envelope containing the attachment reference and wrapped key material.

## Backend guarantees

- object storage receives encrypted blobs only
- API stores metadata only
- plaintext file contents never touch backend business logic
- plaintext file keys are never stored server-side

## Current scaffold limitation

The upload/download tickets in this repository are development scaffolds. Production should replace them with hardened presigned URL generation, bucket policy enforcement, content validation, and malware handling appropriate to encrypted-blob workflows.
