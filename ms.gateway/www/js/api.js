/**
 * API client for the blog microservices.
 * All requests go through the gateway (same origin).
 */
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

  // --- Auth ---
  async login(email, password) {
    const r = await this.post('/api/auth/login', { Email: email, Password: password });
    if (r.ok) {
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
