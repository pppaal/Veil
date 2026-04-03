import { BadRequestException, Injectable } from '@nestjs/common';
import { AppConfigService } from '../../common/config/app-config.service';
import {
  DeleteObjectCommand,
  GetObjectCommand,
  HeadObjectCommand,
  PutObjectCommand,
  S3Client,
} from '@aws-sdk/client-s3';
import { getSignedUrl } from '@aws-sdk/s3-request-presigner';

export interface AttachmentUploadTarget {
  url: string;
  headers: Record<string, string>;
  contentType: string;
  sizeBytes: number;
  expiresAt: string;
}

export interface AttachmentDownloadTarget {
  url: string;
  expiresAt: string;
}

export interface AttachmentObjectMetadata {
  attachmentId: string;
  sha256: string;
  sizeBytes: number;
  contentType: string;
}

export interface AttachmentObjectHead {
  exists: boolean;
  sizeBytes?: number;
  contentType?: string;
  metadata?: Record<string, string>;
}

export const ATTACHMENT_STORAGE_GATEWAY = Symbol('ATTACHMENT_STORAGE_GATEWAY');

export interface AttachmentStorageGateway {
  createUploadTarget(
    storageKey: string,
    metadata: AttachmentObjectMetadata,
  ): Promise<AttachmentUploadTarget>;

  headObject(storageKey: string): Promise<AttachmentObjectHead>;

  deleteObject(storageKey: string): Promise<void>;

  createDownloadTarget(storageKey: string): Promise<AttachmentDownloadTarget>;
}

@Injectable()
export class S3AttachmentStorageGateway implements AttachmentStorageGateway {
  constructor(private readonly config: AppConfigService) {
    this.internalClient = new S3Client({
      region: config.s3Region,
      endpoint: config.s3Endpoint,
      forcePathStyle: true,
      credentials: {
        accessKeyId: config.s3AccessKey,
        secretAccessKey: config.s3SecretKey,
      },
    });
    this.publicClient = new S3Client({
      region: config.s3Region,
      endpoint: config.s3PublicEndpoint,
      forcePathStyle: true,
      credentials: {
        accessKeyId: config.s3AccessKey,
        secretAccessKey: config.s3SecretKey,
      },
    });
  }

  private readonly internalClient: S3Client;
  private readonly publicClient: S3Client;
  private static readonly expirySeconds = 600;

  async createUploadTarget(
    storageKey: string,
    metadata: AttachmentObjectMetadata,
  ): Promise<AttachmentUploadTarget> {
    const command = new PutObjectCommand({
      Bucket: this.config.s3Bucket,
      Key: storageKey,
      ContentType: metadata.contentType,
      ContentLength: metadata.sizeBytes,
      CacheControl: 'no-store',
      Metadata: {
        encrypted: 'true',
        sha256: metadata.sha256,
        'attachment-id': metadata.attachmentId,
      },
    });
    const expiresAt = new Date(
      Date.now() + S3AttachmentStorageGateway.expirySeconds * 1000,
    ).toISOString();

    return {
      url: await getSignedUrl(this.publicClient, command, {
        expiresIn: S3AttachmentStorageGateway.expirySeconds,
      }),
      headers: {
        'Content-Type': metadata.contentType,
        'Content-Length': String(metadata.sizeBytes),
        'Cache-Control': 'no-store',
        'x-amz-meta-encrypted': 'true',
        'x-amz-meta-sha256': metadata.sha256,
        'x-amz-meta-attachment-id': metadata.attachmentId,
      },
      contentType: metadata.contentType,
      sizeBytes: metadata.sizeBytes,
      expiresAt,
    };
  }

  async headObject(storageKey: string): Promise<AttachmentObjectHead> {
    try {
      const response = await this.internalClient.send(
        new HeadObjectCommand({
          Bucket: this.config.s3Bucket,
          Key: storageKey,
        }),
      );
      return {
        exists: true,
        sizeBytes:
            response.ContentLength == null ? undefined : Number(response.ContentLength),
        contentType: response.ContentType,
        metadata: response.Metadata ?? {},
      };
    } catch (error) {
      if (this.isNotFound(error)) {
        return { exists: false };
      }
      throw new BadRequestException('Attachment object probe failed');
    }
  }

  async createDownloadTarget(storageKey: string): Promise<AttachmentDownloadTarget> {
    const expiresAt = new Date(
      Date.now() + S3AttachmentStorageGateway.expirySeconds * 1000,
    ).toISOString();
    const url = await getSignedUrl(
      this.publicClient,
      new GetObjectCommand({
        Bucket: this.config.s3Bucket,
        Key: storageKey,
      }),
      { expiresIn: S3AttachmentStorageGateway.expirySeconds },
    );

    return {
      url,
      expiresAt,
    };
  }

  async deleteObject(storageKey: string): Promise<void> {
    await this.internalClient.send(
      new DeleteObjectCommand({
        Bucket: this.config.s3Bucket,
        Key: storageKey,
      }),
    );
  }

  private isNotFound(error: unknown): boolean {
    if (typeof error !== 'object' || error === null) {
      return false;
    }
    const value = error as { name?: string; $metadata?: { httpStatusCode?: number } };
    return (
      value.name === 'NotFound' ||
      value.name === 'NoSuchKey' ||
      value.$metadata?.httpStatusCode === 404
    );
  }
}
