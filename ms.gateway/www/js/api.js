/**
 * API client for the blog microservices.
 * All requests go through the gateway (same origin).
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
  // Alphabet: ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789./
  // No padding.

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
      if (bits >= 8) {
        bits -= 8;
        out.push((val >>> bits) & 0xff);
      }
    }
    return new Uint8Array(out);
  },

  passlibEncode(bytes) {
    const alph = this._PASSLIB64;
    let out = '', bits = 0, val = 0;
    for (const b of bytes) {
      val = (val << 8) | b;
      bits += 8;
      while (bits >= 6) {
        bits -= 6;
        out += alph[(val >>> bits) & 0x3f];
      }
    }
    if (bits > 0) out += alph[(val << (6 - bits)) & 0x3f];
    return out;
  },

  // -- base64uri (RFC 4648 §5, no padding) --

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
    const sig = await crypto.subtle.sign('HMAC', k, data);
    return new Uint8Array(sig);
  },

  async sha256(data) {
    const h = await crypto.subtle.digest('SHA-256', data);
    return new Uint8Array(h);
  },

  xorBytes(a, b) {
    const out = new Uint8Array(a.length);
    for (let i = 0; i < a.length; i++) out[i] = a[i] ^ b[i];
    return out;
  },

  // -- MCF parsing --

  parseMcfInfo(mcfInfo) {
    // Expected: $pbkdf2-sha256$rounds$passlibBase64Salt$
    const parts = mcfInfo.split('$').filter(s => s !== '');
    if (parts.length < 3 || !parts[0].startsWith('pbkdf2'))
      throw new Error('Unsupported MCF format: ' + mcfInfo);
    return {
      algorithm: parts[0],
      rounds: parseInt(parts[1], 10),
      saltB64: parts[2],
      salt: this.passlibDecode(parts[2])
    };
  },

  // -- SCRAM-MCF proof computation --
  // Replicates mORMot2's ScramClientProof / ScramClientServerAuth
  //
  // HmacSha256U joins messages with '|' separator:
  //   HMAC-SHA256(key, msg[0] + "|" + msg[1] + ...)

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

  async computeProof(email, password, mcfInfo, serverNonce) {
    const enc = new TextEncoder();
    // 1. Parse MCF info and derive key via PBKDF2
    const mcf = this.parseMcfInfo(mcfInfo);
    const derivedKey = await this.pbkdf2Sha256(
      password, mcf.salt, mcf.rounds, 32);
    // 2. Reconstruct full MCF hash string
    const checksum = this.passlibEncode(derivedKey);
    const mcfHash = mcfInfo + checksum;
    const mcfHashBytes = enc.encode(mcfHash);
    // 3. ClientKey = HMAC-SHA256(mcfHash, email + "|" + "Client Key")
    const clientKey = await this.hmacSha256U(mcfHashBytes, [email, 'Client Key']);
    // 4. StoredKey = SHA256(ClientKey)
    const storedKey = await this.sha256(clientKey);
    // 5. ClientSignature = HMAC-SHA256(StoredKey, [email, serverNonce])
    const clientSig = await this.hmacSha256U(storedKey, [email, serverNonce]);
    // 6. ClientProof = ClientKey XOR ClientSignature
    const clientProof = this.xorBytes(clientKey, clientSig);
    // 7. ServerKey = HMAC-SHA256(mcfHash, email + "|" + "Server Key")
    const serverKey = await this.hmacSha256U(mcfHashBytes, [email, 'Server Key']);
    return {
      clientProof: this.base64uriEncode(clientProof),
      // Saved for mutual authentication
      _clientSig: clientSig,
      _serverKey: serverKey
    };
  },

  verifyServerProof(serverProofB64, clientSig, serverKey) {
    const proof = this.base64uriDecode(serverProofB64);
    const recovered = this.xorBytes(proof, clientSig);
    // Compare recovered with expected serverKey
    if (recovered.length !== serverKey.length) return false;
    let diff = 0;
    for (let i = 0; i < recovered.length; i++) diff |= recovered[i] ^ serverKey[i];
    return diff === 0;
  }
};

// ============================================================
//  API client
// ============================================================

const API = {
  token: localStorage.getItem('blog_token') || null,
  userId: parseInt(localStorage.getItem('blog_userId')) || null,

  /** Base fetch with optional auth header */
  async request(path, options = {}) {
    const headers = options.headers || {};
    headers['Content-Type'] = headers['Content-Type'] || 'application/json';
    if (this.token) {
      headers['Authorization'] = 'Bearer ' + this.token;
    }
    const resp = await fetch(path, { ...options, headers });
    const text = await resp.text();
    let data = null;
    try { data = JSON.parse(text); } catch { data = text; }
    return { status: resp.status, ok: resp.ok, data };
  },

  get(path)            { return this.request(path); },
  post(path, body)     { return this.request(path, { method: 'POST', body: JSON.stringify(body) }); },
  put(path, body)      { return this.request(path, { method: 'PUT', body: JSON.stringify(body) }); },
  del(path)            { return this.request(path, { method: 'DELETE' }); },

  // --- Auth (SCRAM-MCF) ---

  async login(email, password) {
    // Phase 1: request challenge
    const c = await this.post('/api/auth/challenge', { Email: email });
    if (!c.ok || !c.data.McfInfo || !c.data.ServerNonce) {
      return { ok: false, data: { error: 'Challenge failed' } };
    }
    // Phase 2: compute SCRAM proof (PBKDF2 runs in browser)
    const proof = await SCRAM.computeProof(
      email, password, c.data.McfInfo, c.data.ServerNonce);
    // Phase 3: send proof, receive JWT
    const r = await this.post('/api/auth/authenticate', {
      Email: email,
      ServerNonce: c.data.ServerNonce,
      ClientProof: proof.clientProof
    });
    if (r.ok) {
      // Phase 4: verify server proof (mutual authentication)
      if (!SCRAM.verifyServerProof(
        r.data.ServerProof, proof._clientSig, proof._serverKey)) {
        return { ok: false, data: { error: 'Server authentication failed' } };
      }
      this.token = r.data.token;
      this.userId = r.data.userId;
      localStorage.setItem('blog_token', this.token);
      localStorage.setItem('blog_userId', this.userId);
    }
    return r;
  },

  logout() {
    this.token = null;
    this.userId = null;
    localStorage.removeItem('blog_token');
    localStorage.removeItem('blog_userId');
  },

  isLoggedIn() { return !!this.token; },

  // --- Posts ---
  getPosts(page = 1, limit = 10)  { return this.get(`/api/posts?page=${page}&limit=${limit}&status=1`); },
  getPost(id)                      { return this.get(`/api/posts/${id}`); },
  getPostBySlug(slug)              { return this.get(`/api/posts/by-slug/${slug}`); },
  getMyPosts(page = 1)             { return this.get(`/api/posts?page=${page}&limit=50&authorId=${this.userId}`); },
  createPost(data)                 { return this.post('/api/posts', data); },
  updatePost(id, data)             { return this.put(`/api/posts/${id}`, data); },
  deletePost(id)                   { return this.del(`/api/posts/${id}`); },

  // --- Tags ---
  getTags()                        { return this.get('/api/tags'); },
  getPostTags(postId)              { return this.get(`/api/posts/${postId}/tags`); },
  setPostTags(postId, tagIds)      { return this.put(`/api/posts/${postId}/tags`, { TagIds: tagIds }); },

  // --- Comments ---
  getComments(postId)              { return this.get(`/api/posts/${postId}/comments`); },
  addComment(postId, data)         { return this.post(`/api/posts/${postId}/comments`, data); },
  getPendingComments()             { return this.get('/api/comments/pending'); },
  approveComment(id)               { return this.put(`/api/comments/${id}/approve`, { ModeratedBy: this.userId }); },
  rejectComment(id)                { return this.put(`/api/comments/${id}/reject`, { ModeratedBy: this.userId }); },

  // --- Users ---
  getUser(id)                      { return this.get(`/api/users/${id}`); },
  updateUser(id, data)             { return this.put(`/api/users/${id}`, data); },

  // --- Media ---
  uploadMedia(fileName, base64Data, altText) {
    return this.post('/api/media/upload', {
      FileName: fileName, FileData: base64Data, AltText: altText
    });
  }
};
