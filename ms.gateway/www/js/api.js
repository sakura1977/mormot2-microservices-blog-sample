/**
 * API client for the blog microservices.
 * Uses mORMot2 SOA (interface-based services) via the gateway.
 *
 * URL format:  POST /api/ServiceName/MethodName
 * Input:       JSON array of positional parameters
 * Output:      JSON object with named out-params + "Result" key
 *
 * Authentication uses SCRAM-MCF (RFC 5802 + MCF extension):
 *   1. Client requests a challenge (MCF format info + server nonce)
 *   2. Client computes PBKDF2 locally, derives SCRAM proof
 *   3. Server verifies proof, returns JWT + server proof
 *   4. Client verifies server proof (mutual authentication)
 */

// ============================================================
//  SCRAM-MCF cryptographic helpers
// ============================================================

const SCRAM = {

  // -- passlib-compatible base64 (used inside MCF strings) --
  _PASSLIB64: 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789./',

  passlibDecode(str) {
    const lut = {};
    for (let i = 0; i < 64; i++) lut[this._PASSLIB64[i]] = i;
    const out = [];
    let bits = 0, val = 0;
    for (const ch of str) {
      if (lut[ch] === undefined) continue;
      val = (val << 6) | lut[ch];
      bits += 6;
      if (bits >= 8) { bits -= 8; out.push((val >>> bits) & 0xff); }
    }
    return new Uint8Array(out);
  },

  passlibEncode(bytes) {
    const alph = this._PASSLIB64;
    let out = '', bits = 0, val = 0;
    for (const b of bytes) {
      val = (val << 8) | b; bits += 8;
      while (bits >= 6) { bits -= 6; out += alph[(val >>> bits) & 0x3f]; }
    }
    if (bits > 0) out += alph[(val << (6 - bits)) & 0x3f];
    return out;
  },

  // -- base64uri (RFC 4648 section 5, no padding) --
  base64uriEncode(bytes) {
    const bin = String.fromCharCode(...bytes);
    return btoa(bin).replace(/\+/g, '-').replace(/\//g, '_').replace(/=+$/, '');
  },
  base64uriDecode(str) {
    const b64 = str.replace(/-/g, '+').replace(/_/g, '/');
    const pad = (4 - b64.length % 4) % 4;
    const bin = atob(b64 + '='.repeat(pad));
    return Uint8Array.from(bin, c => c.charCodeAt(0));
  },

  // -- low-level crypto via Web Crypto API --
  async pbkdf2Sha256(password, salt, rounds, keyLen) {
    const enc = new TextEncoder();
    const keyMaterial = await crypto.subtle.importKey(
      'raw', enc.encode(password), 'PBKDF2', false, ['deriveBits']);
    const bits = await crypto.subtle.deriveBits(
      { name: 'PBKDF2', salt, iterations: rounds, hash: 'SHA-256' },
      keyMaterial, keyLen * 8);
    return new Uint8Array(bits);
  },
  async hmacSha256(key, data) {
    const k = await crypto.subtle.importKey(
      'raw', key, { name: 'HMAC', hash: 'SHA-256' }, false, ['sign']);
    return new Uint8Array(await crypto.subtle.sign('HMAC', k, data));
  },
  async sha256(data) {
    return new Uint8Array(await crypto.subtle.digest('SHA-256', data));
  },
  xorBytes(a, b) {
    const out = new Uint8Array(a.length);
    for (let i = 0; i < a.length; i++) out[i] = a[i] ^ b[i];
    return out;
  },

  // -- MCF parsing --
  parseMcfInfo(mcfInfo) {
    const parts = mcfInfo.split('$').filter(s => s !== '');
    if (parts.length < 3 || !parts[0].startsWith('pbkdf2'))
      throw new Error('Unsupported MCF format: ' + mcfInfo);
    return {
      algorithm: parts[0], rounds: parseInt(parts[1], 10),
      saltB64: parts[2], salt: this.passlibDecode(parts[2])
    };
  },

  // -- HMAC-SHA256 with pipe-separated messages (mORMot2 convention) --
  async hmacSha256U(key, messages) {
    const enc = new TextEncoder();
    const parts = messages.map(m => enc.encode(m));
    const sep = enc.encode('|');
    let total = 0;
    parts.forEach((p, i) => { total += p.length; if (i < parts.length - 1) total += 1; });
    const data = new Uint8Array(total);
    let off = 0;
    parts.forEach((p, i) => {
      data.set(p, off); off += p.length;
      if (i < parts.length - 1) { data.set(sep, off); off += 1; }
    });
    return this.hmacSha256(key, data);
  },

  // -- SCRAM-MCF proof computation --
  async computeProof(email, password, mcfInfo, serverNonce) {
    const enc = new TextEncoder();
    const mcf = this.parseMcfInfo(mcfInfo);
    const derivedKey = await this.pbkdf2Sha256(password, mcf.salt, mcf.rounds, 32);
    const checksum = this.passlibEncode(derivedKey);
    const mcfHash = mcfInfo + checksum;
    const mcfHashBytes = enc.encode(mcfHash);
    const clientKey = await this.hmacSha256U(mcfHashBytes, [email, 'Client Key']);
    const storedKey = await this.sha256(clientKey);
    const clientSig = await this.hmacSha256U(storedKey, [email, serverNonce]);
    const clientProof = this.xorBytes(clientKey, clientSig);
    const serverKey = await this.hmacSha256U(mcfHashBytes, [email, 'Server Key']);
    return {
      clientProof: this.base64uriEncode(clientProof),
      _clientSig: clientSig, _serverKey: serverKey
    };
  },

  verifyServerProof(serverProofB64, clientSig, serverKey) {
    const proof = this.base64uriDecode(serverProofB64);
    const recovered = this.xorBytes(proof, clientSig);
    if (recovered.length !== serverKey.length) return false;
    let diff = 0;
    for (let i = 0; i < recovered.length; i++) diff |= recovered[i] ^ serverKey[i];
    return diff === 0;
  }
};

// ============================================================
//  mORMot2 SOA helper
// ============================================================

/**
 * Generates a UUID v4 (random) for use as a correlation ID.
 * Uses crypto.randomUUID() when available, falls back to a manual implementation.
 */
function newCorrelationId() {
  if (window.crypto && typeof window.crypto.randomUUID === 'function') {
    return window.crypto.randomUUID();
  }
  // RFC 4122 v4 fallback
  return 'xxxxxxxx-xxxx-4xxx-yxxx-xxxxxxxxxxxx'.replace(/[xy]/g, c => {
    const r = Math.random() * 16 | 0;
    const v = c === 'x' ? r : (r & 0x3 | 0x8);
    return v.toString(16);
  });
}

/**
 * Calls a mORMot2 interface-based service method.
 * @param {string} service  - Interface name (e.g. 'Auth', 'Post')
 * @param {string} method   - Method name (e.g. 'Challenge', 'GetList')
 * @param {Array}  params   - Positional input parameters as JSON array
 * @returns {object} { ok, status, data, correlationId } where data is the parsed result object
 */
async function soaCall(service, method, params = []) {
  const correlationId = newCorrelationId();
  const headers = {
    'Content-Type': 'application/json',
    'X-Correlation-Id': correlationId
  };
  if (API.token) headers['Authorization'] = 'Bearer ' + API.token;
  const resp = await fetch(`/api/${service}/${method}`, {
    method: 'POST',
    headers,
    body: JSON.stringify(params)
  });
  const text = await resp.text();
  let data = null;
  try { data = JSON.parse(text); } catch { data = text; }
  // Server may echo a different ID if the gateway generated one (shouldn't happen since we always send one)
  const serverCorrelationId = resp.headers.get('X-Correlation-Id') || correlationId;
  // Trace per-call in the browser console -- handy when grep'ing the server logs
  console.debug(`[${serverCorrelationId}] ${service}.${method} -> ${resp.status}`);
  return { status: resp.status, ok: resp.ok, data, correlationId: serverCorrelationId };
}

// ============================================================
//  API client
// ============================================================

const API = {
  token: localStorage.getItem('blog_token') || null,
  userId: parseInt(localStorage.getItem('blog_userId')) || null,

  // --- Auth (SCRAM-MCF) ---

  async login(email, password) {
    // Phase 1: request challenge
    const c = await soaCall('Auth', 'Challenge', [email]);
    if (!c.ok || !c.data.aMcfInfo || !c.data.aServerNonce) {
      return { ok: false, data: { error: 'Challenge failed' } };
    }
    // Phase 2: compute SCRAM proof (PBKDF2 runs in browser)
    const proof = await SCRAM.computeProof(
      email, password, c.data.aMcfInfo, c.data.aServerNonce);
    // Phase 3: send proof, receive JWT
    const r = await soaCall('Auth', 'Authenticate',
      [email, c.data.aServerNonce, proof.clientProof]);
    if (r.ok && r.data.Result) {
      // Phase 4: verify server proof (mutual authentication)
      if (!SCRAM.verifyServerProof(
        r.data.aServerProof, proof._clientSig, proof._serverKey)) {
        return { ok: false, data: { error: 'Server authentication failed' } };
      }
      this.token = r.data.aToken;
      this.userId = r.data.aUserId;
      localStorage.setItem('blog_token', this.token);
      localStorage.setItem('blog_userId', this.userId);
      return { ok: true, data: r.data };
    }
    return { ok: false, data: { error: 'Invalid credentials' } };
  },

  logout() {
    this.token = null;
    this.userId = null;
    localStorage.removeItem('blog_token');
    localStorage.removeItem('blog_userId');
  },

  isLoggedIn() { return !!this.token; },

  // --- Posts ---
  async getPosts(page = 1, limit = 10) {
    const r = await soaCall('Post', 'GetList', [page, limit, 1, 0]);
    // Result contains the paginated JSON
    if (r.ok) r.data = typeof r.data.Result === 'string'
      ? JSON.parse(r.data.Result) : r.data.Result;
    return r;
  },
  async getPost(id) {
    // Use aggregated endpoint for full post with author/tags/comments
    const r = await soaCall('Blog', 'GetPostFull', [id]);
    if (r.ok) r.data = typeof r.data.Result === 'string'
      ? JSON.parse(r.data.Result) : r.data.Result;
    return r;
  },
  async getPostBySlug(slug) {
    const r = await soaCall('Post', 'GetBySlug', [slug]);
    if (r.ok) r.data = typeof r.data.Result === 'string'
      ? JSON.parse(r.data.Result) : r.data.Result;
    return r;
  },
  async getMyPosts(page = 1) {
    const r = await soaCall('Post', 'GetList', [page, 50, 0, this.userId]);
    if (r.ok) r.data = typeof r.data.Result === 'string'
      ? JSON.parse(r.data.Result) : r.data.Result;
    return r;
  },
  async createPost(data) {
    return soaCall('Post', 'Add', [data]);
  },
  async updatePost(id, data) {
    return soaCall('Post', 'Update', [id, data]);
  },
  async deletePost(id) {
    return soaCall('Post', 'Remove', [id]);
  },

  // --- Tags ---
  async getTags() {
    const r = await soaCall('Tag', 'GetAll', []);
    if (r.ok) r.data = typeof r.data.Result === 'string'
      ? JSON.parse(r.data.Result) : r.data.Result;
    return r;
  },
  async getPostTags(postId) {
    const r = await soaCall('Tag', 'GetByPost', [postId]);
    if (r.ok) r.data = typeof r.data.Result === 'string'
      ? JSON.parse(r.data.Result) : r.data.Result;
    return r;
  },
  async setPostTags(postId, tagIds) {
    return soaCall('Tag', 'SetPostTags', [postId, tagIds]);
  },
  async getPostsByTag(tagId) {
    const r = await soaCall('Blog', 'GetPostsByTag', [tagId]);
    if (r.ok) r.data = typeof r.data.Result === 'string'
      ? JSON.parse(r.data.Result) : r.data.Result;
    return r;
  },

  // --- Comments ---
  async getComments(postId) {
    const r = await soaCall('Comment', 'GetByPost', [postId]);
    if (r.ok) r.data = typeof r.data.Result === 'string'
      ? JSON.parse(r.data.Result) : r.data.Result;
    return r;
  },
  async addComment(postId, data) {
    return soaCall('Comment', 'Add', [postId, data]);
  },
  async getPendingComments() {
    const r = await soaCall('Comment', 'GetPending', []);
    if (r.ok) r.data = typeof r.data.Result === 'string'
      ? JSON.parse(r.data.Result) : r.data.Result;
    return r;
  },
  async approveComment(id) {
    return soaCall('Comment', 'Approve', [id, this.userId]);
  },
  async rejectComment(id) {
    return soaCall('Comment', 'Reject', [id, this.userId]);
  },

  // --- Users ---
  async getUser(id) {
    const r = await soaCall('User', 'Get', [id]);
    if (r.ok) r.data = typeof r.data.Result === 'string'
      ? JSON.parse(r.data.Result) : r.data.Result;
    return r;
  },
  async updateUser(id, data) {
    return soaCall('User', 'Update', [id, data]);
  },

  // --- Media ---
  async uploadMedia(fileName, base64Data, altText) {
    return soaCall('Media', 'Upload', [fileName, base64Data, altText, this.userId]);
  },

  // --- Analytics ---
  async getOverview() {
    const r = await soaCall('Analytics', 'GetOverview', []);
    if (r.ok) r.data = typeof r.data.Result === 'string'
      ? JSON.parse(r.data.Result) : r.data.Result;
    return r;
  },
  async getAuthorStats() {
    const r = await soaCall('Analytics', 'GetAuthorStats', []);
    if (r.ok) r.data = typeof r.data.Result === 'string'
      ? JSON.parse(r.data.Result) : r.data.Result;
    return r;
  },
  async getTagCloud() {
    const r = await soaCall('Analytics', 'GetTagCloud', []);
    if (r.ok) r.data = typeof r.data.Result === 'string'
      ? JSON.parse(r.data.Result) : r.data.Result;
    return r;
  },
  async getCommentActivity() {
    const r = await soaCall('Analytics', 'GetCommentActivity', []);
    if (r.ok) r.data = typeof r.data.Result === 'string'
      ? JSON.parse(r.data.Result) : r.data.Result;
    return r;
  },
  async getRecentPostsFull(limit = 5) {
    const r = await soaCall('Analytics', 'GetRecentPostsFull', [limit]);
    if (r.ok) r.data = typeof r.data.Result === 'string'
      ? JSON.parse(r.data.Result) : r.data.Result;
    return r;
  },

  // --- Logs (central logging service via gateway proxy) ---
  async logsByCorrelationId(id) {
    const r = await soaCall('LogQuery', 'ByCorrelationId', [id]);
    if (r.ok) r.data = typeof r.data.Result === 'string'
      ? JSON.parse(r.data.Result) : r.data.Result;
    return r;
  },
  async logsRecent(filter = {}) {
    const r = await soaCall('LogQuery', 'Recent', [filter]);
    if (r.ok) r.data = typeof r.data.Result === 'string'
      ? JSON.parse(r.data.Result) : r.data.Result;
    return r;
  },
  async logsSearch(text, limit = 100) {
    const r = await soaCall('LogQuery', 'Search', [text, limit]);
    if (r.ok) r.data = typeof r.data.Result === 'string'
      ? JSON.parse(r.data.Result) : r.data.Result;
    return r;
  },
  async logsStats() {
    const r = await soaCall('LogQuery', 'Stats', []);
    if (r.ok) r.data = typeof r.data.Result === 'string'
      ? JSON.parse(r.data.Result) : r.data.Result;
    return r;
  },

  // --- Live log stream (WebSocket via custom 'blog-logs' chat protocol) ---
  //
  // openLogStream() opens a persistent WebSocket connection to the gateway. As soon as the
  // socket is open, we send a tiny "hello" frame which the gateway uses to register us as an
  // active subscriber. From then on, every new log entry is pushed by the server as a JSON
  // frame of the shape {"entry": {...TLogEntryDto...}}.
  //
  // Why a custom chat protocol instead of mORMot2's built-in 'synopsejson'?
  // mORMot2's TWebSocketProtocolJson is REST-over-WebSocket with mORMot2-specific framing
  // (call IDs, callback registration sequence). It is designed for TRestHttpClientWebsockets,
  // not for raw `new WebSocket(...)` from a browser. The pragmatic fix is a tiny custom chat
  // protocol on the last hop only -- the Pascal stack (Producer -> ms.logs -> Gateway) keeps
  // using mORMot2's proper binary callbacks. See `.claude/event-driven.md` for the full story.
  openLogStream(onEntry, onClose) {
    const wsProtocol = location.protocol === 'https:' ? 'wss:' : 'ws:';
    const url = `${wsProtocol}//${location.host}/`;
    let ws;
    let reconnectTimer = null;
    let closed = false;

    const connect = () => {
      ws = new WebSocket(url, 'blog-logs');

      ws.onopen = () => {
        console.debug('[logstream] WebSocket open, sending hello');
        // The gateway registers a sender as an active subscriber on the first frame it receives.
        // The frame content is irrelevant -- we only need the server to know we exist.
        ws.send('hello');
      };

      ws.onmessage = (event) => {
        let frame;
        try {
          frame = JSON.parse(event.data);
        } catch (e) {
          console.warn('[logstream] Could not parse frame:', event.data);
          return;
        }
        if (frame && frame.entry) {
          onEntry(frame.entry);
        }
      };

      ws.onerror = (event) => {
        console.warn('[logstream] WebSocket error:', event);
      };

      ws.onclose = () => {
        if (closed) return;
        console.debug('[logstream] WebSocket closed, reconnecting in 2s');
        if (onClose) onClose();
        reconnectTimer = setTimeout(connect, 2000);
      };
    };

    connect();

    return {
      close() {
        closed = true;
        if (reconnectTimer) clearTimeout(reconnectTimer);
        if (ws && ws.readyState !== WebSocket.CLOSED) ws.close();
      }
    };
  }
};
