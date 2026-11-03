import 'dotenv/config';
import pg from 'pg';

const { Pool } = pg;
export const db = process.env.DATABASE_URL
  ? new Pool({
      connectionString: process.env.DATABASE_URL,
      max: 5,
      connectionTimeoutMillis: 12000,
      idleTimeoutMillis: 30000
    })
  : null;

export function requireDb(req, res, next) {
  if (!db) return res.status(503).json({ error: 'DATABASE_URL chưa được cấu hình trên server.' });
  next();
}
