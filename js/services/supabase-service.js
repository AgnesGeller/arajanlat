import { SUPABASE_URL, SUPABASE_KEY } from '../config.js';
export const configured = Boolean(SUPABASE_URL && SUPABASE_KEY && window.supabase?.createClient);
export const db = configured ? window.supabase.createClient(SUPABASE_URL, SUPABASE_KEY, {
  auth: { autoRefreshToken: true, persistSession: true, detectSessionInUrl: true }
}) : null;
export async function rows(table, query = x => x.select('*')) {
  const { data, error } = await query(db.from(table));
  if (error) throw error;
  return data;
}
export async function rpc(name, args) {
  const { data, error } = await db.rpc(name, args);
  if (error) throw error;
  return data;
}
