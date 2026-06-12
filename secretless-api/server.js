const express = require('express');
const { ManagedIdentityCredential } = require('@azure/identity');
const { createRemoteJWKSet, jwtVerify } = require('jose');

const app = express();
const credential = new ManagedIdentityCredential();

app.disable('x-powered-by');
app.use(express.json({ limit: '32kb' }));

const expectedTenantId = process.env.EXPECTED_TENANT_ID || '';
const expectedAudiences = (process.env.EXPECTED_TOKEN_AUDIENCES || '')
  .split(',')
  .map(value => value.trim())
  .filter(Boolean);
const requiredScope = process.env.REQUIRED_SCOPE || 'TapPortal.RequestTap';
const allowedOrigins = (process.env.ALLOWED_ORIGIN || '')
  .split(',')
  .map(value => value.trim())
  .filter(Boolean);
const tapLifetimeMinutes = Number(process.env.TAP_LIFETIME_MINUTES || '60');

function applyCors(req, res) {
  const origin = req.headers.origin;
  if (origin && allowedOrigins.includes(origin)) {
    res.setHeader('Access-Control-Allow-Origin', origin);
    res.setHeader('Vary', 'Origin');
    res.setHeader('Access-Control-Allow-Methods', 'POST,OPTIONS');
    res.setHeader('Access-Control-Allow-Headers', 'Authorization,Content-Type');
  }
}

app.use((req, res, next) => {
  applyCors(req, res);
  if (req.method === 'OPTIONS') {
    return res.status(204).end();
  }

  return next();
});

app.get('/healthz', (_req, res) => {
  res.status(200).json({ ok: true });
});

function getBearerToken(req) {
  const header = req.headers.authorization || '';
  if (!header.startsWith('Bearer ')) {
    return null;
  }

  return header.slice('Bearer '.length).trim() || null;
}

function ensureTenantConfigured() {
  if (!expectedTenantId) {
    throw new Error('EXPECTED_TENANT_ID is not configured.');
  }

  if (expectedAudiences.length === 0) {
    throw new Error('EXPECTED_TOKEN_AUDIENCES is not configured.');
  }
}

async function validateAccessToken(req) {
  ensureTenantConfigured();

  const token = getBearerToken(req);
  if (!token) {
    const error = new Error('Authentication is required.');
    error.status = 401;
    throw error;
  }

  const issuer = `https://login.microsoftonline.com/${expectedTenantId}/v2.0`;
  const jwks = createRemoteJWKSet(new URL(`https://login.microsoftonline.com/${expectedTenantId}/discovery/v2.0/keys`));
  const { payload } = await jwtVerify(token, jwks, {
    issuer,
    audience: expectedAudiences
  });

  const tokenScopes = String(payload.scp || '').split(' ').filter(Boolean);
  if (!tokenScopes.includes(requiredScope)) {
    const error = new Error('The signed-in token is missing the required API scope.');
    error.status = 403;
    throw error;
  }

  const objectId = payload.oid || payload.sub;
  if (!objectId) {
    const error = new Error('The access token is missing the signed-in user object ID.');
    error.status = 401;
    throw error;
  }

  return {
    objectId,
    displayName: payload.name || payload.preferred_username || 'Signed-in user'
  };
}

async function getGraphAccessToken() {
  const token = await credential.getToken('https://graph.microsoft.com/.default');
  if (!token?.token) {
    throw new Error('Managed identity could not obtain a Microsoft Graph access token.');
  }

  return token.token;
}

async function createTemporaryAccessPass(userId) {
  const graphToken = await getGraphAccessToken();
  const response = await fetch(`https://graph.microsoft.com/v1.0/users/${encodeURIComponent(userId)}/authentication/temporaryAccessPassMethods`, {
    method: 'POST',
    headers: {
      'Authorization': `Bearer ${graphToken}`,
      'Content-Type': 'application/json'
    },
    body: JSON.stringify({
      lifetimeInMinutes: tapLifetimeMinutes,
      isUsableOnce: true
    })
  });

  const contentType = response.headers.get('content-type') || '';
  const payload = contentType.includes('application/json')
    ? await response.json()
    : { error: { message: await response.text() } };

  if (!response.ok) {
    const error = new Error(payload?.error?.message || 'Failed to create TAP through Microsoft Graph.');
    error.status = response.status;
    throw error;
  }

  return payload;
}

app.post('/api/request-tap', async (req, res) => {
  try {
    const identity = await validateAccessToken(req);
    const tap = await createTemporaryAccessPass(identity.objectId);

    return res.status(200).json({
      success: true,
      temporaryAccessPass: tap.temporaryAccessPass,
      lifetimeInMinutes: tap.lifetimeInMinutes,
      startDateTime: tap.startDateTime,
      isUsableOnce: tap.isUsableOnce
    });
  } catch (error) {
    const status = Number(error.status) || 500;
    const safeMessage = status >= 500
      ? 'The backend could not complete the TAP request.'
      : (error.message || 'Authentication failed.');

    console.error('request-tap failed', error);
    return res.status(status).json({
      success: false,
      error: safeMessage
    });
  }
});

const port = Number(process.env.WEBSITES_PORT || process.env.PORT || '8080');
app.listen(port, () => {
  console.log(`Secretless TAP API listening on port ${port}`);
});