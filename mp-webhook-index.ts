// DabiasTech · mp-webhook
// Nombre de la función: mp-webhook
// Verify JWT: OFF (Mercado Pago no envía JWT de Supabase)

import { createClient } from "https://esm.sh/@supabase/supabase-js@2.49.1";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, GET, OPTIONS",
};

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }

  try {
    const MP_ACCESS_TOKEN = Deno.env.get("MP_ACCESS_TOKEN");
    const SUPABASE_URL = Deno.env.get("SUPABASE_URL")!;
    const SERVICE_KEY = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;

    if (!MP_ACCESS_TOKEN) {
      return json({ error: "Falta MP_ACCESS_TOKEN" }, 500);
    }

    const admin = createClient(SUPABASE_URL, SERVICE_KEY);
    const url = new URL(req.url);

    let paymentId = url.searchParams.get("data.id") || url.searchParams.get("id");
    let topic = url.searchParams.get("type") || url.searchParams.get("topic");

    if (req.method === "POST") {
      try {
        const body = await req.json();
        topic = body?.type || body?.action || topic;
        paymentId = body?.data?.id?.toString?.() || body?.data?.id || body?.id || paymentId;
      } catch (_) { /* query only */ }
    }

    if (!paymentId) {
      return json({ ok: true, skipped: true });
    }

    if (topic && !String(topic).toLowerCase().includes("payment")) {
      return json({ ok: true, ignored: topic });
    }

    const mpRes = await fetch(`https://api.mercadopago.com/v1/payments/${paymentId}`, {
      headers: { Authorization: `Bearer ${MP_ACCESS_TOKEN}` },
    });
    const payment = await mpRes.json();
    if (!mpRes.ok) {
      console.error("MP get payment", payment);
      return json({ error: "payment fetch failed", detail: payment }, 502);
    }

    const status = payment.status as string;
    const ext = String(payment.external_reference || "");
    const siteMatch = ext.match(/site:([0-9a-f-]{36})/i);
    const siteId = siteMatch?.[1] || payment.metadata?.site_id;

    console.log("MP payment", paymentId, status, siteId);

    if (status === "approved" && siteId) {
      const { error } = await admin.rpc("activate_site_from_payment", {
        p_site_id: siteId,
        p_payment_id: String(paymentId),
        p_mp_status: status,
        p_raw: payment,
      });
      if (error) console.error("activate error", error);
    } else if (siteId && (status === "rejected" || status === "cancelled")) {
      await admin
        .from("payments")
        .update({
          status: status === "rejected" ? "rejected" : "cancelled",
          mp_payment_id: String(paymentId),
          mp_status: status,
          raw: payment,
        })
        .eq("site_id", siteId)
        .eq("status", "pending");
    }

    return json({ ok: true, status, siteId });
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
