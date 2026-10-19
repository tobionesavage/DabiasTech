// DabiasTech · mp-checkout
// Nombre de la función: mp-checkout
// Verify JWT: ON (el usuario debe estar logueado)

import { createClient } from "https://esm.sh/@supabase/supabase-js@2.49.1";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

const PLAN_PRICES: Record<string, { name: string; amount: number }> = {
  starter: { name: "Starter", amount: 35000 },
  pro: { name: "Pro", amount: 65000 },
  premium: { name: "Premium", amount: 110000 },
};

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }

  try {
    const MP_ACCESS_TOKEN = Deno.env.get("MP_ACCESS_TOKEN");
    const SITE_URL = (Deno.env.get("SITE_URL") || "https://dabiastech.netlify.app").replace(/\/$/, "");
    const SUPABASE_URL = Deno.env.get("SUPABASE_URL")!;
    const SERVICE_KEY = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
    const ANON_KEY = Deno.env.get("SUPABASE_ANON_KEY")!;

    if (!MP_ACCESS_TOKEN) {
      return json({ error: "Falta secret MP_ACCESS_TOKEN" }, 500);
    }

    const authHeader = req.headers.get("Authorization");
    const apikey = req.headers.get("apikey") || ANON_KEY;
    if (!authHeader) {
      return json({ error: "No autenticado. Iniciá sesión en DabiasTech." }, 401);
    }

    const userClient = createClient(SUPABASE_URL, apikey, {
      global: { headers: { Authorization: authHeader, apikey } },
    });
    const admin = createClient(SUPABASE_URL, SERVICE_KEY);

    const { data: { user }, error: userErr } = await userClient.auth.getUser();
    if (userErr || !user) {
      return json({ error: "Sesión inválida. Volvé a ingresar." }, 401);
    }

    const body = await req.json().catch(() => ({}));
    const site_id = body?.site_id as string;
    if (!site_id) return json({ error: "site_id requerido" }, 400);

    const { data: site, error: siteErr } = await admin
      .from("sites")
      .select("id, name, plan, owner_id, status")
      .eq("id", site_id)
      .single();

    if (siteErr || !site) return json({ error: "Sitio no encontrado" }, 404);
    if (site.owner_id !== user.id) return json({ error: "No sos el dueño de este sitio" }, 403);

    const planInfo = PLAN_PRICES[site.plan] || PLAN_PRICES.starter;
    const external_reference = `site:${site.id}:plan:${site.plan}:user:${user.id}`;

    const { data: paymentRow, error: payInsErr } = await admin
      .from("payments")
      .insert({
        site_id: site.id,
        owner_id: user.id,
        plan: site.plan,
        amount: planInfo.amount,
        currency: "ARS",
        status: "pending",
        external_reference,
      })
      .select("id")
      .single();

    if (payInsErr) {
      console.error(payInsErr);
      return json({ error: "No se pudo registrar el pago. ¿Ejecutaste supabase-mp.sql?" }, 500);
    }

    const notification_url = `${SUPABASE_URL}/functions/v1/mp-webhook`;
    const preference = {
      items: [{
        id: site.plan,
        title: `DabiasTech · Plan ${planInfo.name} · ${site.name}`,
        description: "Mensualidad 30 días",
        quantity: 1,
        currency_id: "ARS",
        unit_price: Number(planInfo.amount),
      }],
      payer: { email: user.email },
      external_reference,
      metadata: {
        site_id: site.id,
        payment_row_id: paymentRow.id,
        plan: site.plan,
        user_id: user.id,
      },
      back_urls: {
        success: `${SITE_URL}/?mp=success&site=${site.id}`,
        failure: `${SITE_URL}/?mp=failure&site=${site.id}`,
        pending: `${SITE_URL}/?mp=pending&site=${site.id}`,
      },
      auto_return: "approved",
      notification_url,
      statement_descriptor: "DABIASTECH",
    };

    const mpRes = await fetch("https://api.mercadopago.com/checkout/preferences", {
      method: "POST",
      headers: {
        Authorization: `Bearer ${MP_ACCESS_TOKEN}`,
        "Content-Type": "application/json",
      },
      body: JSON.stringify(preference),
    });
    const mpJson = await mpRes.json();
    if (!mpRes.ok) {
      console.error("MP error", mpJson);
      return json({ error: "Mercado Pago rechazó la preferencia", detail: mpJson }, 502);
    }

    await admin.from("payments").update({ mp_preference_id: mpJson.id }).eq("id", paymentRow.id);

    const sandbox = (Deno.env.get("MP_SANDBOX") || "true") === "true";
    const init_point = sandbox
      ? (mpJson.sandbox_init_point || mpJson.init_point)
      : mpJson.init_point;

    return json({
      init_point,
      preference_id: mpJson.id,
      payment_id: paymentRow.id,
      amount: planInfo.amount,
    });
  } catch (e) {
    console.error(e);
    return json({ error: String(e) }, 500);
  }
});

function json(data: unknown, status = 200) {
  return new Response(JSON.stringify(data), {
    status,
    headers: { ...corsHeaders, "Content-Type": "application/json" },
  });
}
