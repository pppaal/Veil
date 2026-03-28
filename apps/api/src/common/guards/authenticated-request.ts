import type { Request } from 'express';

export interface AuthContext {
  userId: string;
  deviceId: string;
  handle: string;
}

export interface AuthenticatedRequest extends Request {
  auth: AuthContext;
}
