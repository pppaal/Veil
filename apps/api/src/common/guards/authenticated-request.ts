import type { Request } from 'express';

export interface AuthContext {
  userId: string;
  deviceId: string;
  handle: string;
  jti?: string;
  exp?: number;
}

export interface AuthenticatedRequest extends Request {
  auth: AuthContext;
}
