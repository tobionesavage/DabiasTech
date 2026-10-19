# Mercado Pago · DabiasTech

## 1. Credenciales (Mercado Pago)
1. Entrá a https://www.mercadopago.com.ar/developers/panel
2. Creá una aplicación (o usá una existente)
3. Copiá:
   - **Access Token** de producción (o TEST para pruebas) → APP_USR-...
4. Webhooks (opcional pero recomendado):
   - URL: `https://ykxrkiklhpcmxtrgwfla.supabase.co/functions/v1/mp-webhook`
   - Eventos: `payment`

## 2. SQL en Supabase
SQL Editor → ejecutá el archivo `supabase-mp.sql`

## 3. Secrets en Supabase
Project Settings → Edge Functions → Secrets (o CLI):

```
MP_ACCESS_TOKEN=APP_USR-tu-access-token
SITE_URL=https://dabiastech.netlify.app
MP_SANDBOX=true
```

Poné `MP_SANDBOX=false` cuando pases a producción real.
SUPABASE_URL, SUPABASE_ANON_KEY y SUPABASE_SERVICE_ROLE_KEY ya existen en Edge Functions.

## 4. Deploy de funciones

Con Supabase CLI:

```bash
supabase login
supabase link --project-ref ykxrkiklhpcmxtrgwfla

# crear carpetas
mkdir -p supabase/functions/mp-checkout supabase/functions/mp-webhook
# copiar mp-checkout-index.ts → supabase/functions/mp-checkout/index.ts
# copiar mp-webhook-index.ts → supabase/functions/mp-webhook/index.ts

supabase secrets set MP_ACCESS_TOKEN=APP_USR-... SITE_URL=https://dabiastech.netlify.app MP_SANDBOX=true

supabase functions deploy mp-checkout
supabase functions deploy mp-webhook --no-verify-jwt
```

Sin CLI: Dashboard → Edge Functions → Create function → pegá el código de cada archivo.

## 5. Front
Subí el `index.html` actualizado a Netlify.

## Flujo
1. Cliente → Pagar → Edge Function crea preferencia
2. Redirect a Mercado Pago
3. Paga → vuelve a dabiastech.netlify.app/?mp=success
4. Webhook de MP → activa el sitio 30 días (status act)

## Pruebas (sandbox)
Usá tarjetas de prueba de MP:
https://www.mercadopago.com.ar/developers/es/docs/checkout-pro/additional-content/test-cards
