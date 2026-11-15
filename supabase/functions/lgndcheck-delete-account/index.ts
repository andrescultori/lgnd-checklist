import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { createClient } from "jsr:@supabase/supabase-js@2";

// Exclui a PRÓPRIA conta de quem chama (identificada pelo JWT). Nunca aceita um userId do cliente.
// Perfil, itens, presets e backups saem em cascata (FK ON DELETE CASCADE a partir de auth.users).

const PROJECT_URL = Deno.env.get("SUPABASE_URL")!;
const SERVICE_ROLE_KEY = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
const ANON_KEY = Deno.env.get("SUPABASE_ANON_KEY")!;

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

function json(data: unknown, status = 200) {
  return new Response(JSON.stringify(data), {
    status,
    headers: { "Content-Type": "application/json", ...corsHeaders },
  });
}

Deno.serve(async (req: Request) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: corsHeaders });
  if (req.method !== "POST") return json({ error: "Método não permitido." }, 405);

  try {
    const jwt = (req.headers.get("Authorization") ?? "").replace(/^Bearer\s+/i, "");
    if (!jwt) return json({ error: "Não autenticado." }, 401);

    const userClient = createClient(PROJECT_URL, ANON_KEY, {
      global: { headers: { Authorization: `Bearer ${jwt}` } },
    });
    const { data, error } = await userClient.auth.getUser();
    if (error || !data?.user) return json({ error: "Sessão inválida." }, 401);

    let body: Record<string, unknown> = {};
    try { body = await req.json(); } catch { /* sem corpo */ }
    if (body.confirm !== "EXCLUIR") return json({ error: "Confirmação ausente." }, 400);

    const admin = createClient(PROJECT_URL, SERVICE_ROLE_KEY);
    const { error: delErr } = await admin.auth.admin.deleteUser(data.user.id);
    if (delErr) return json({ error: "Não foi possível excluir a conta." }, 500);
    return json({ ok: true });
  } catch (e) {
    console.error(e);
    return json({ error: "Erro inesperado." }, 500);
  }
});
