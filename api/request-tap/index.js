const OBJECT_ID_CLAIMS = [
  'oid',
  'http://schemas.microsoft.com/identity/claims/objectidentifier'
];
const TENANT_ID_CLAIMS = ['tid'];
const NAME_CLAIMS = ['name'];

function jsonResponse(status, body) {
  return {
    status,
    headers: {
      'Content-Type': 'application/json'
    },
    body
  };
}

function getHeader(headers, name) {
  if (!headers) {
    return '';
  }

  const exact = headers[name];
  if (exact) {
    return exact;
  }

  const lowerName = name.toLowerCase();
  const headerKey = Object.keys(headers).find(key => key.toLowerCase() === lowerName);
  return headerKey ? headers[headerKey] : '';
}

function getClaimValue(claims, claimTypes) {
  if (!Array.isArray(claims)) {
    return null;
  }

  for (const claimType of claimTypes) {
    const match = claims.find(claim => claim.typ === claimType);
    if (match && match.val) {
      return match.val;
    }
  }

  return null;
}

function parseClientPrincipal(req) {
  const encodedPrincipal = getHeader(req.headers, 'x-ms-client-principal');
  if (!encodedPrincipal) {
    return null;
  }

  try {
    return JSON.parse(Buffer.from(encodedPrincipal, 'base64').toString('utf8'));
  } catch {
    throw new Error('Invalid Static Web Apps principal header.');
  }
}

function getIdentityFromPrincipal(principal) {
  if (!principal) {
    return null;
  }

  const objectId = getClaimValue(principal.claims, OBJECT_ID_CLAIMS) || principal.userId || null;
  const tenantId = getClaimValue(principal.claims, TENANT_ID_CLAIMS);
  const displayName = getClaimValue(principal.claims, NAME_CLAIMS) || principal.userDetails || 'Signed-in user';

  if (!objectId) {
    throw new Error('Signed-in identity is missing the object ID claim.');
  }

  return {
    objectId,
    tenantId,
    displayName,
    source: 'swa-principal'
  };
}

async function resolveIdentity(req) {
  return getIdentityFromPrincipal(parseClientPrincipal(req));
}

function buildLogicAppUrl() {
  const baseUrl = process.env.LOGIC_APP_BASE_URL;
  const apiVersion = process.env.LOGIC_APP_API_VERSION;
  const scopePath = process.env.LOGIC_APP_SP;
  const sharedAccessVersion = process.env.LOGIC_APP_SV;
  const signature = process.env.LOGIC_APP_SIG;

  if (baseUrl && apiVersion && scopePath && sharedAccessVersion && signature) {
    return `${baseUrl}?api-version=${encodeURIComponent(apiVersion)}&sp=${encodeURIComponent(scopePath)}&sv=${encodeURIComponent(sharedAccessVersion)}&sig=${encodeURIComponent(signature)}`;
  }

  return process.env.LOGIC_APP_URL || '';
}

module.exports = async function (context, req) {
  try {
    if ((req.method || '').toUpperCase() !== 'POST') {
      return jsonResponse(405, {
        success: false,
        error: 'Method not allowed.'
      });
    }

    const logicAppUrl = buildLogicAppUrl();
    if (!logicAppUrl) {
      context.log.error('Logic App callback app settings are not configured.');
      return jsonResponse(500, {
        success: false,
        error: 'API is not configured.'
      });
    }

    const identity = await resolveIdentity(req);
    if (!identity?.objectId) {
      return jsonResponse(401, {
        success: false,
        error: 'Authentication is required.'
      });
    }

    if (process.env.EXPECTED_TENANT_ID && identity.tenantId && identity.tenantId !== process.env.EXPECTED_TENANT_ID) {
      return jsonResponse(403, {
        success: false,
        error: 'Authenticated tenant is not allowed.'
      });
    }

    const logicAppResponse = await fetch(logicAppUrl, {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json'
      },
      body: JSON.stringify({
        userId: identity.objectId
      })
    });

    const contentType = logicAppResponse.headers.get('content-type') || '';
    const payload = contentType.includes('application/json')
      ? await logicAppResponse.json()
      : { success: false, error: await logicAppResponse.text() };

    if (!logicAppResponse.ok || !payload.success) {
      return jsonResponse(logicAppResponse.status || 400, {
        success: false,
        error: payload.error || 'Failed to create TAP.'
      });
    }

    return jsonResponse(200, payload);
  } catch (error) {
    context.log.error('request-tap failed', error);
    return jsonResponse(401, {
      success: false,
      error: error.message || 'Authentication failed.'
    });
  }
};
