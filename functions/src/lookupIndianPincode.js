/**
 * India Post PIN lookup — server-side proxy for Flutter / web clients.
 *
 * Clients call Firebase HTTPS (validated TLS). Upstream api.postalpincode.in
 * currently serves an expired certificate; only this module performs the
 * outbound fetch (isolated server egress — not client-side TLS bypass).
 */
const https = require("https");

const PIN_API_HOST = "api.postalpincode.in";
const TIMEOUT_MS = 8000;
const CACHE_TTL_MS = 30 * 24 * 60 * 60 * 1000;
const MAX_ATTEMPTS = 2;

/** @type {Map<string, { payload: object, expiresAt: number }>} */
const memoryCache = new Map();

const STATE_ALIASES = {
  orissa: "Odisha",
  odisa: "Odisha",
  pondicherry: "Puducherry",
  puducherry: "Puducherry",
  uttaranchal: "Uttarakhand",
  chattisgarh: "Chhattisgarh",
  chhatisgarh: "Chhattisgarh",
  "nct of delhi": "Delhi",
  "national capital territory of delhi": "Delhi",
  "new delhi": "Delhi",
  "jammu and kashmir": "Jammu & Kashmir",
  "andaman and nicobar islands": "Andaman & Nicobar Islands",
  "dadra and nagar haveli": "Dadra & Nagar Haveli and Daman & Diu",
  "daman and diu": "Dadra & Nagar Haveli and Daman & Diu",
  "telangana state": "Telangana",
  "andhra pradesh state": "Andhra Pradesh",
};

const UPSTREAM_AGENT = new https.Agent({
  // Remove when India Post renews api.postalpincode.in TLS certificate.
  rejectUnauthorized: false,
});

function normalizePin(raw) {
  return String(raw || "").replace(/\D/g, "");
}

function fieldAsString(map, keys) {
  for (const key of keys) {
    const v = map[key];
    if (v == null) continue;
    const t = String(v).trim();
    if (t) return t;
  }
  return "";
}

function pickStateFromOfficeMap(map) {
  return fieldAsString(map, ["State", "state", "Circle", "circle"]);
}

function decodeApiRoot(body) {
  let decoded;
  try {
    decoded = JSON.parse(body);
  } catch {
    return null;
  }
  if (Array.isArray(decoded)) {
    if (!decoded.length) return null;
    const first = decoded[0];
    return first && typeof first === "object" ? first : null;
  }
  if (decoded && typeof decoded === "object") return decoded;
  return null;
}

function coercePostOfficeMaps(raw) {
  if (raw == null) return [];
  if (raw && typeof raw === "object" && !Array.isArray(raw)) {
    return [raw];
  }
  if (!Array.isArray(raw)) return [];
  return raw.filter((item) => item && typeof item === "object");
}

function normalizeStateLabel(raw) {
  return String(raw || "")
    .trim()
    .toLowerCase()
    .replace(/\s+/g, " ")
    .replace(/ and /g, " & ");
}

function matchIndianState(apiState) {
  const t = String(apiState || "").trim();
  if (!t) return "";
  const alias = STATE_ALIASES[normalizeStateLabel(t)];
  if (alias) return alias;
  return t;
}

function resolveCity(office) {
  const candidates = [
    office.region,
    office.division,
    office.block,
    office.name,
    office.district,
  ].filter(Boolean);
  return candidates[0] || "";
}

function parseIndiaPostBody(body) {
  const rootMap = decodeApiRoot(body);
  if (!rootMap) return null;

  const status = fieldAsString(rootMap, ["Status", "status"]);
  if (!status || status.toLowerCase() !== "success") {
    return { invalid: status && status.toLowerCase() !== "success" };
  }

  const officesRaw =
    rootMap.PostOffice ??
    rootMap.postOffice ??
    rootMap.Postoffices ??
    rootMap.postoffices;
  const officeMaps = coercePostOfficeMaps(officesRaw);
  if (!officeMaps.length) return null;

  const offices = [];
  for (const map of officeMaps) {
    const name = fieldAsString(map, ["Name", "name"]);
    const district = fieldAsString(map, ["District", "district"]);
    const state = pickStateFromOfficeMap(map);
    const country = fieldAsString(map, ["Country", "country"]) || "India";
    const region = fieldAsString(map, ["Region", "region"]);
    const division = fieldAsString(map, ["Division", "division"]);
    const block = fieldAsString(map, ["Block", "block"]);
    const circle = fieldAsString(map, ["Circle", "circle"]);
    if (!district && !name) continue;

    const apiStateRaw = state || circle;
    const matchedState = matchIndianState(apiStateRaw);
    const city = resolveCity({
      region,
      division,
      block,
      name,
      district,
    });

    offices.push({
      name,
      district,
      state: apiStateRaw,
      matchedState,
      country,
      region,
      division,
      block,
      circle,
      city,
      area: name,
    });
  }

  if (!offices.length) return null;
  return { offices };
}

function uniqueAreaNames(offices) {
  const seen = new Set();
  const names = [];
  for (const o of offices) {
    const n = String(o.name || "").trim();
    if (!n || seen.has(n)) continue;
    seen.add(n);
    names.push(n);
  }
  return names;
}

function buildSuccessPayload(pin, offices) {
  const primary = offices[0];
  const areas = uniqueAreaNames(offices);
  return {
    success: true,
    pin,
    state: primary.matchedState || primary.state,
    city: primary.city,
    area: primary.area,
    country: primary.country || "India",
    district: primary.district,
    areas,
    postOffices: offices.map((o) => ({
      name: o.name,
      district: o.district,
      state: o.state,
      matchedState: o.matchedState,
      country: o.country,
      region: o.region,
      division: o.division,
      block: o.block,
      circle: o.circle,
      city: o.city,
      area: o.area,
    })),
  };
}

function fetchPostalPincodeApiBody(pin) {
  return new Promise((resolve, reject) => {
    const req = https.request(
      {
        hostname: PIN_API_HOST,
        path: `/pincode/${pin}`,
        method: "GET",
        headers: {
          Accept: "application/json",
          "User-Agent":
            "BrahminVivaahaVedika/1.0 (CloudFunctions; PIN lookup)",
        },
        timeout: TIMEOUT_MS,
        agent: UPSTREAM_AGENT,
      },
      (res) => {
        let body = "";
        res.on("data", (chunk) => {
          body += chunk;
        });
        res.on("end", () => {
          if (res.statusCode >= 200 && res.statusCode < 300) {
            resolve(body);
            return;
          }
          reject(
            Object.assign(new Error(`PIN API HTTP ${res.statusCode}`), {
              code: "HTTP_ERROR",
            })
          );
        });
      }
    );
    req.on("timeout", () => {
      req.destroy();
      reject(
        Object.assign(new Error("PIN API timeout"), { code: "TIMEOUT" })
      );
    });
    req.on("error", (err) => {
      reject(
        Object.assign(err, {
          code: err.code === "ETIMEDOUT" ? "TIMEOUT" : "NETWORK",
        })
      );
    });
    req.end();
  });
}

function readCache(pin) {
  const entry = memoryCache.get(pin);
  if (!entry) return null;
  if (Date.now() > entry.expiresAt) {
    memoryCache.delete(pin);
    return null;
  }
  return entry.payload;
}

function writeCache(pin, payload) {
  memoryCache.set(pin, {
    payload,
    expiresAt: Date.now() + CACHE_TTL_MS,
  });
}

/**
 * @param {FirebaseFirestore.Firestore | null} db
 * @param {string} pin
 */
async function readPincodeFromFirestore(db, pin) {
  if (!db) return null;
  try {
    const snap = await db.collection("indian_pincodes").doc(pin).get();
    if (!snap.exists) return null;
    const data = snap.data() || {};
    const storedOffices = data.postOffices ?? data.offices;
    if (data.success === true && Array.isArray(storedOffices) && storedOffices.length) {
      return {
        ...buildSuccessPayload(pin, storedOffices),
        source: "firestore",
      };
    }
  } catch (e) {
    console.warn("indian_pincodes read failed:", e?.message || e);
  }
  return null;
}

/**
 * @param {FirebaseFirestore.Firestore | null} db
 * @param {string} pin
 * @param {object} payload
 */
async function writePincodeToFirestore(db, pin, payload) {
  if (!db || !payload?.success) return;
  try {
    await db.collection("indian_pincodes").doc(pin).set(
      {
        ...payload,
        synced_at: new Date().toISOString(),
        updated_at: new Date().toISOString(),
      },
      { merge: true }
    );
  } catch (e) {
    console.warn("indian_pincodes write failed:", e?.message || e);
  }
}

/**
 * @param {string} pin 6-digit PIN
 * @param {{ db?: FirebaseFirestore.Firestore }} [options]
 * @returns {Promise<object>}
 */
async function lookupIndianPincodePayload(pin, options = {}) {
  const db = options.db || null;
  const cleaned = normalizePin(pin);
  if (cleaned.length !== 6) {
    return { success: false, error: "invalid" };
  }

  const cached = readCache(cleaned);
  if (cached) return cached;

  const firestoreHit = await readPincodeFromFirestore(db, cleaned);
  if (firestoreHit) {
    writeCache(cleaned, firestoreHit);
    return firestoreHit;
  }

  let lastError;
  for (let attempt = 1; attempt <= MAX_ATTEMPTS; attempt++) {
    try {
      const body = await fetchPostalPincodeApiBody(cleaned);
      const parsed = parseIndiaPostBody(body);
      if (parsed?.invalid) {
        return { success: false, error: "invalid" };
      }
      if (!parsed?.offices?.length) {
        lastError = new Error("Malformed PIN API response");
        if (attempt < MAX_ATTEMPTS) {
          await new Promise((r) => setTimeout(r, 350));
          continue;
        }
        return { success: false, error: "unavailable" };
      }
      const payload = buildSuccessPayload(cleaned, parsed.offices);
      writeCache(cleaned, payload);
      await writePincodeToFirestore(db, cleaned, payload);
      return { ...payload, source: payload.source || "upstream" };
    } catch (e) {
      lastError = e;
      if (e.code === "TIMEOUT" || e.code === "ETIMEDOUT") {
        if (attempt < MAX_ATTEMPTS) {
          await new Promise((r) => setTimeout(r, 350));
          continue;
        }
        return { success: false, error: "timeout" };
      }
      if (attempt < MAX_ATTEMPTS) {
        await new Promise((r) => setTimeout(r, 350));
        continue;
      }
    }
  }

  if (lastError?.code === "TIMEOUT" || lastError?.code === "ETIMEDOUT") {
    return { success: false, error: "timeout" };
  }
  return { success: false, error: "unavailable" };
}

/**
 * @param {import('firebase-functions').region.RegionBuilder} fnAsia
 * @param {{ db?: FirebaseFirestore.Firestore }} [options]
 */
function createLookupIndianPincodeCallable(fnAsia, options = {}) {
  const db = options.db || null;
  return fnAsia.https.onCall(async (data) => {
    const pin = normalizePin(data?.pin);
    return lookupIndianPincodePayload(pin, { db });
  });
}

module.exports = {
  createLookupIndianPincodeCallable,
  lookupIndianPincodePayload,
  parseIndiaPostBody,
  normalizePin,
};
