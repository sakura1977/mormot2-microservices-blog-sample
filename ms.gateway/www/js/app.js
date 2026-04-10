/**
 * Blog SPA -- Vanilla JavaScript.
 * Routing, rendering and event handling.
 */

const $ = (sel) => document.querySelector(sel);
const $$ = (sel) => document.querySelectorAll(sel);
const app = $('#app');

// === Router ===
// Real path routing via the History API. The gateway serves index.html for any
// unmatched path (SPA fallback in ms.gateway.server.pas), so deep-links reload cleanly.
const routes = [
  { re: /^\/$/,                             handler: ()  => loadPosts(1) },
  { re: /^\/page\/(\d+)$/,                  handler: (m) => loadPosts(parseInt(m[1])) },
  { re: /^\/posts\/(\d+)$/,                 handler: (m) => loadPost(parseInt(m[1])) },
  { re: /^\/tags$/,                         handler: ()  => loadTags() },
  { re: /^\/tags\/(\d+)$/,                  handler: (m) => loadPostsByTag(parseInt(m[1])) },
  { re: /^\/authors\/(\d+)$/,               handler: (m) => loadAuthor(parseInt(m[1])) },
  { re: /^\/dashboard$/,                    handler: ()  => loadDashboard() },
  { re: /^\/dashboard\/moderation$/,        handler: ()  => loadModeration() },
  { re: /^\/dashboard\/profile$/,           handler: ()  => loadProfileEditor() },
  { re: /^\/analytics$/,                    handler: ()  => loadAnalytics() },
  { re: /^\/analytics\/authors$/,           handler: ()  => loadAuthorStats() },
  { re: /^\/analytics\/tags$/,              handler: ()  => loadTagCloudView() },
  { re: /^\/analytics\/comments$/,          handler: ()  => loadCommentActivityView() },
  { re: /^\/analytics\/recent$/,            handler: ()  => loadRecentPostsFullView() },
  { re: /^\/logs$/,                         handler: ()  => loadLogs() },
  { re: /^\/logs\/correlation\/([^/]+)$/,   handler: (m) => loadLogsByCorrelation(decodeURIComponent(m[1])) }
];

function navigate(path, opts) {
  const current = location.pathname + location.search;
  if (path !== current) {
    if (opts && opts.replace)
      history.replaceState({}, '', path);
    else
      history.pushState({}, '', path);
  }
  dispatchRoute(path);
}

function dispatchRoute(path) {
  const pathname = path.split('?')[0];
  // Only the /logs view keeps a live WebSocket. Close it when navigating anywhere else.
  if (!pathname.startsWith('/logs'))
    closeActiveLogStream();
  for (const r of routes) {
    const m = pathname.match(r.re);
    if (m) { r.handler(m); return; }
  }
  // Unknown path: fall back to the home list.
  loadPosts(1);
}

window.addEventListener('popstate', () => dispatchRoute(location.pathname + location.search));

// Global link interceptor: turn every same-origin <a href="/..."> into a
// pushState navigation while keeping the real href so right-click > "Copy link"
// and sharing work the normal way.
document.addEventListener('click', (e) => {
  const a = e.target.closest('a');
  if (!a) return;
  const href = a.getAttribute('href');
  if (!href || href.startsWith('#') || /^[a-z]+:\/\//i.test(href) || a.target === '_blank') return;
  if (e.defaultPrevented || e.ctrlKey || e.metaKey || e.shiftKey || e.altKey || e.button !== 0) return;
  e.preventDefault();
  navigate(href);
});

function setPageMeta(title, description) {
  document.title = title ? `${title} — Blog` : 'Blog';
  if (description) {
    const m = document.querySelector('meta[name="description"]');
    if (m) m.setAttribute('content', description);
  }
}

// === Initialization ===
document.addEventListener('DOMContentLoaded', () => {
  updateAuthNav();
  dispatchRoute(location.pathname + location.search);
});

function updateAuthNav() {
  const nav = $('#auth-nav');
  if (API.isLoggedIn()) {
    nav.innerHTML = `
      <a href="/dashboard">Dashboard</a>
      <a href="#" onclick="doLogout(); return false;">Sign Out</a>
    `;
  } else {
    nav.innerHTML = `<a href="#" onclick="showLogin(); return false;">Sign In</a>`;
  }
}

// === Post List (Home Page) ===
let currentPage = 1;

async function loadPosts(page = 1) {
  currentPage = page;
  setPageMeta('Home', 'Blog - Microservices Demo');
  app.innerHTML = '<div class="loading">Loading posts...</div>';
  const r = await API.getPosts(page);
  if (!r.ok) { app.innerHTML = '<p class="error">Failed to load posts.</p>'; return; }

  const posts = r.data.Items || r.data || [];
  const total = r.data.Total || 0;
  const totalPages = Math.ceil(total / 10);

  if (posts.length === 0) {
    app.innerHTML = '<p>No posts yet.</p>';
    return;
  }

  let html = '<ul class="post-list">';
  for (const p of posts) {
    const date = p.PublishedAt ? new Date(p.PublishedAt).toLocaleDateString('en') : '';
    html += `
      <li class="post-card">
        <h2><a href="/posts/${p.ID}">${esc(p.Title)}</a></h2>
        <div class="post-meta">${date}</div>
        <p class="post-excerpt">${esc(p.Excerpt || '')}</p>
      </li>`;
  }
  html += '</ul>';

  if (totalPages > 1) {
    html += '<div class="pagination">';
    if (page > 1)
      html += `<a class="btn-outline btn-sm" href="/page/${page - 1}">&laquo; Previous</a>`;
    html += `<span style="padding:.5rem">Page ${page} / ${totalPages}</span>`;
    if (page < totalPages)
      html += `<a class="btn-outline btn-sm" href="/page/${page + 1}">Next &raquo;</a>`;
    html += '</div>';
  }

  app.innerHTML = html;
}

// === Single Post (aggregated) ===
async function loadPost(id) {
  app.innerHTML = '<div class="loading">Loading post...</div>';
  const r = await API.getPost(id);
  if (!r.ok) { app.innerHTML = '<p class="error">Post not found.</p>'; return; }

  const p = r.data;
  const postId = p.ID || id;
  setPageMeta(p.MetaTitle || p.Title, p.MetaDescription || p.Excerpt);
  const date = p.PublishedAt ? new Date(p.PublishedAt).toLocaleDateString('en') : '';
  const author = p.Author || {};
  const tags = p.Tags || [];
  const comments = p.Comments || [];

  let tagsHtml = '';
  if (p.TagsUnavailable)
    tagsHtml = '<p class="error" style="margin:.5rem 0">Tags could not be loaded.</p>';
  else if (tags.length > 0)
    tagsHtml = '<div style="margin:.5rem 0">' +
      tags.map(t => `<a class="tag" href="/tags/${t.ID}">${esc(t.Name || '')}</a>`).join('') +
      '</div>';

  let authorHtml = '';
  if (p.AuthorUnavailable)
    authorHtml = ' &mdash; <span style="color:var(--text-light)">(Author unavailable)</span>';
  else if (author.DisplayName)
    authorHtml = ' &mdash; <a href="/authors/' + author.ID + '">' + esc(author.DisplayName) + '</a>';

  let commentsHtml = '';
  if (p.CommentsUnavailable) {
    commentsHtml = '<p class="error">Comments could not be loaded.</p>';
  } else if (comments.length > 0) {
    for (const c of comments) {
      const cDate = c.CreatedAt ? new Date(c.CreatedAt).toLocaleDateString('en') : '';
      commentsHtml += `
        <div class="comment">
          <span class="comment-author">${esc(c.AuthorName)}</span>
          <span class="comment-date">${cDate}</span>
          <div class="comment-body">${esc(c.Body)}</div>
        </div>`;
    }
  } else {
    commentsHtml = '<p style="color:var(--text-light)">No comments yet.</p>';
  }

  const commentsFormHtml = p.CommentsUnavailable ? '' : `
      <div class="comment-form">
        <h4>Write a Comment</h4>
        <form onsubmit="submitComment(event, ${postId})">
          <label for="c-name">Name</label>
          <input type="text" id="c-name" required>
          <label for="c-email">Email (optional)</label>
          <input type="email" id="c-email">
          <label for="c-body">Comment</label>
          <textarea id="c-body" rows="4" required></textarea>
          <button type="submit">Submit</button>
          <p id="c-msg" class="success hidden" style="margin-top:.5rem"></p>
        </form>
      </div>`;

  app.innerHTML = `
    <article class="post-full">
      <h1>${esc(p.Title)}</h1>
      <div class="post-meta">
        ${date}${authorHtml}
      </div>
      ${tagsHtml}
      <div class="post-body">${esc(p.Body)}</div>
    </article>

    <section class="comments-section">
      <h3>Comments${p.CommentsUnavailable ? '' : ' (' + comments.length + ')'}</h3>
      ${commentsHtml}
      ${commentsFormHtml}
    </section>

    <p style="margin-top:2rem"><a href="/">&laquo; Back to overview</a></p>
  `;
}

// === Submit Comment ===
async function submitComment(e, postId) {
  e.preventDefault();
  const data = {
    AuthorName: $('#c-name').value,
    AuthorEmail: $('#c-email').value,
    Body: $('#c-body').value
  };
  const r = await API.addComment(postId, data);
  const msg = $('#c-msg');
  if (r.ok) {
    msg.textContent = 'Comment submitted. It will appear after review.';
    msg.classList.remove('hidden');
    $('#c-name').value = '';
    $('#c-email').value = '';
    $('#c-body').value = '';
  } else {
    msg.textContent = 'Failed to submit comment.';
    msg.className = 'error';
  }
}

// === Tags ===
async function loadTags() {
  setPageMeta('Tags');
  app.innerHTML = '<div class="loading">Loading tags...</div>';
  const r = await API.getTags();
  if (!r.ok) { app.innerHTML = '<p class="error">Error.</p>'; return; }

  const tags = Array.isArray(r.data) ? r.data : [];
  if (tags.length === 0) {
    app.innerHTML = '<h2>Tags</h2><p>No tags available.</p>';
    return;
  }
  let html = '<h2>Tags</h2><ul class="tag-list">';
  for (const t of tags)
    html += `<li><a class="tag" href="/tags/${t.ID}">${esc(t.Name)}</a></li>`;
  html += '</ul>';
  app.innerHTML = html;
}

async function loadPostsByTag(tagId) {
  app.innerHTML = '<div class="loading">Loading posts...</div>';
  const r = await API.getPostsByTag(tagId);
  if (!r.ok || !r.data || !r.data.Tag) {
    app.innerHTML = '<p class="error">Tag not found.</p>';
    return;
  }

  const tag = r.data.Tag;
  const posts = r.data.Posts || [];
  const tagName = tag.Name || '';
  setPageMeta('Tag: ' + tagName, tag.Description || '');

  let html = `<h2>Tag: ${esc(tagName)}</h2>`;
  if (tag.Description)
    html += `<p>${esc(tag.Description)}</p>`;

  if (posts.length === 0) {
    html += '<p>No posts with this tag.</p>';
  } else {
    html += '<ul class="post-list">';
    for (const p of posts) {
      const date = p.PublishedAt ? new Date(p.PublishedAt).toLocaleDateString('en') : '';
      const author = p.Author ? p.Author.DisplayName : '';
      html += `
        <li class="post-card">
          <h2><a href="/posts/${p.ID}">${esc(p.Title)}</a></h2>
          <div class="post-meta">${date}${author ? ' &mdash; ' + esc(author) : ''}</div>
          <p class="post-excerpt">${esc(p.Excerpt || '')}</p>
        </li>`;
    }
    html += '</ul>';
  }

  html += '<p style="margin-top:1rem"><a href="/tags">&laquo; All Tags</a></p>';
  app.innerHTML = html;
}

// === Author Profile ===
async function loadAuthor(id) {
  app.innerHTML = '<div class="loading">Loading profile...</div>';
  const r = await API.getUser(id);
  if (!r.ok) { app.innerHTML = '<p class="error">Author not found.</p>'; return; }

  const a = r.data;
  setPageMeta(a.DisplayName, a.Bio || '');
  app.innerHTML = `
    <div class="author-card">
      <div class="author-info">
        <h2>${esc(a.DisplayName)}</h2>
        <p class="author-bio">${esc(a.Bio || '')}</p>
        ${a.WebsiteUrl ? '<p><a href="' + esc(a.WebsiteUrl) + '" target="_blank">Website</a></p>' : ''}
      </div>
    </div>
    <h3>Posts</h3>
    <div id="author-posts"><div class="loading">Loading...</div></div>
    <p style="margin-top:1rem"><a href="/">&laquo; Back</a></p>
  `;

  const pr = await soaCall('Post', 'GetList', [1, 50, 0, id]);
  const postsDiv = $('#author-posts');
  if (pr.ok) {
    let postsData = pr.data.Result;
    if (typeof postsData === 'string') postsData = JSON.parse(postsData);
    const items = postsData?.Items || [];
    if (items.length > 0) {
      let ph = '<ul class="post-list">';
      for (const p of items)
        ph += `<li class="post-card"><h2><a href="/posts/${p.ID}">${esc(p.Title)}</a></h2></li>`;
      ph += '</ul>';
      postsDiv.innerHTML = ph;
    } else {
      postsDiv.innerHTML = '<p>No posts.</p>';
    }
  } else {
    postsDiv.innerHTML = '<p>No posts.</p>';
  }
}

// === Login / Logout ===
function showLogin() { $('#login-modal').classList.remove('hidden'); }
function hideLogin() { $('#login-modal').classList.add('hidden'); $('#login-error').classList.add('hidden'); }

async function doLogin(e) {
  e.preventDefault();
  const btn = e.target.querySelector('button[type="submit"]');
  const origText = btn.textContent;
  btn.textContent = 'Signing in\u2026';
  btn.disabled = true;
  try {
    const r = await API.login($('#login-email').value, $('#login-password').value);
    if (r.ok) {
      hideLogin();
      updateAuthNav();
      navigate('/dashboard');
    } else {
      const err = $('#login-error');
      err.textContent = r.data?.error || 'Login failed.';
      err.classList.remove('hidden');
    }
  } finally {
    btn.textContent = origText;
    btn.disabled = false;
  }
}

function doLogout() {
  API.logout();
  updateAuthNav();
  navigate('/');
}

// === Dashboard (authenticated) ===
async function loadDashboard() {
  if (!API.isLoggedIn()) { showLogin(); return; }
  setPageMeta('Dashboard');
  app.innerHTML = '<div class="loading">Loading dashboard...</div>';

  let html = `
    <h2>Dashboard</h2>
    <div class="dashboard-actions">
      <button onclick="clearEditor(); showEditor()">New Post</button>
      <button class="btn-outline" onclick="navigate('/dashboard/moderation')">Comment Moderation</button>
      <button class="btn-outline" onclick="navigate('/dashboard/profile')">Edit Profile</button>
    </div>
    <h3>My Posts</h3>
  `;

  const r = await API.getMyPosts();
  if (r.ok) {
    const posts = r.data.Items || r.data || [];
    if (posts.length === 0) {
      html += '<p>No posts yet. Create your first one!</p>';
    } else {
      html += '<ul class="post-list">';
      for (const p of posts) {
        const statusCls = p.Status === 1 ? 'status-published' : 'status-draft';
        const statusTxt = p.Status === 1 ? 'Published' : 'Draft';
        html += `
          <li class="post-card">
            <div style="display:flex;justify-content:space-between;align-items:center">
              <div>
                <h2 style="display:inline">${esc(p.Title)}</h2>
                <span class="post-status ${statusCls}">${statusTxt}</span>
              </div>
              <div>
                <button class="btn-sm btn-outline" onclick="editPost(${p.ID})">Edit</button>
                <button class="btn-sm btn-danger" onclick="deletePostConfirm(${p.ID})">Delete</button>
              </div>
            </div>
          </li>`;
      }
      html += '</ul>';
    }
  } else {
    html += '<p class="error">Failed to load posts.</p>';
  }
  app.innerHTML = html;
}

// === Post Editor ===
function showEditor() { $('#editor-modal').classList.remove('hidden'); }
function hideEditor() { $('#editor-modal').classList.add('hidden'); }

async function loadEditorTags(selectedIds = []) {
  const container = $('#editor-tags');
  container.innerHTML = 'Loading tags...';
  const r = await API.getTags();
  if (!r.ok) { container.innerHTML = ''; return; }
  const tags = Array.isArray(r.data) ? r.data : [];
  container.innerHTML = tags.map(t => {
    const tid = t.ID;
    const checked = selectedIds.includes(tid) ? ' checked' : '';
    return `<label class="tag-checkbox"><input type="checkbox" value="${tid}"${checked}> ${esc(t.Name)}</label>`;
  }).join('');
  $('#editor-new-tag').value = '';
}

async function addNewTag() {
  const input = $('#editor-new-tag');
  const name = input.value.trim();
  if (!name) return;
  const r = await soaCall('Tag', 'Add', [{ Name: name, Description: '' }]);
  if (r.ok) {
    const newId = r.data.Result;
    const selectedIds = getSelectedTagIds();
    selectedIds.push(newId);
    await loadEditorTags(selectedIds);
  } else {
    alert('Could not create tag: ' + (r.data?.error || ''));
  }
}

function getSelectedTagIds() {
  return Array.from($$('#editor-tags input:checked')).map(cb => parseInt(cb.value));
}

async function clearEditor() {
  $('#editor-id').value = '';
  $('#editor-title').textContent = 'New Post';
  $('#editor-post-title').value = '';
  $('#editor-excerpt').value = '';
  $('#editor-body').value = '';
  $('#editor-meta-title').value = '';
  $('#editor-meta-desc').value = '';
  $('#editor-meta-keywords').value = '';
  $('#editor-status').value = '0';
  await loadEditorTags();
}

async function editPost(id) {
  const r = await API.getPost(id);
  if (!r.ok) { alert('Post not found.'); return; }
  const p = r.data;
  const postTags = (p.Tags || []).map(t => t.ID);
  $('#editor-id').value = id;
  $('#editor-title').textContent = 'Edit Post';
  $('#editor-post-title').value = p.Title || '';
  $('#editor-excerpt').value = p.Excerpt || '';
  $('#editor-body').value = p.Body || '';
  $('#editor-meta-title').value = p.MetaTitle || '';
  $('#editor-meta-desc').value = p.MetaDescription || '';
  $('#editor-meta-keywords').value = p.MetaKeywords || '';
  $('#editor-status').value = String(p.Status || 0);
  await loadEditorTags(postTags);
  showEditor();
}

async function savePost(e) {
  e.preventDefault();
  const id = $('#editor-id').value;
  const data = {
    Title: $('#editor-post-title').value,
    Body: $('#editor-body').value,
    Excerpt: $('#editor-excerpt').value,
    MetaTitle: $('#editor-meta-title').value,
    MetaDescription: $('#editor-meta-desc').value,
    MetaKeywords: $('#editor-meta-keywords').value,
    Status: parseInt($('#editor-status').value),
    AuthorId: API.userId
  };

  let r;
  if (id) {
    r = await API.updatePost(id, data);
  } else {
    r = await API.createPost(data);
  }

  if (r.ok) {
    const postId = id || r.data?.Result;
    if (postId) {
      const tagIds = getSelectedTagIds();
      await API.setPostTags(postId, tagIds);
    }
    hideEditor();
    navigate('/dashboard');
  } else {
    alert('Error: ' + (r.data?.error || 'Save failed.'));
  }
}

async function deletePostConfirm(id) {
  if (!confirm('Really delete this post?')) return;
  await API.deletePost(id);
  loadDashboard();
}

// === Comment Moderation ===
async function loadModeration() {
  setPageMeta('Comment Moderation');
  app.innerHTML = '<div class="loading">Loading pending comments...</div>';
  const r = await API.getPendingComments();
  if (!r.ok) { app.innerHTML = '<p class="error">Error.</p>'; return; }

  const comments = Array.isArray(r.data) ? r.data : [];
  let html = '<h2>Comment Moderation</h2>';
  if (comments.length === 0) {
    html += '<p>No pending comments.</p>';
  } else {
    html += `<p>${comments.length} pending comment(s)</p>`;
    for (const c of comments) {
      const cDate = c.CreatedAt ? new Date(c.CreatedAt).toLocaleDateString('en') : '';
      html += `
        <div class="post-card moderation-item">
          <div>
            <strong>${esc(c.AuthorName)}</strong> <span class="comment-date">${cDate}</span>
            <br>Post #${c.PostId}
            <div class="comment-body">${esc(c.Body)}</div>
          </div>
          <div class="moderation-actions">
            <button class="btn-sm btn-success" onclick="moderateComment(${c.ID}, 'approve')">Approve</button>
            <button class="btn-sm btn-danger" onclick="moderateComment(${c.ID}, 'reject')">Reject</button>
          </div>
        </div>`;
    }
  }
  html += '<p style="margin-top:1rem"><a href="/dashboard">&laquo; Dashboard</a></p>';
  app.innerHTML = html;
}

async function moderateComment(id, action) {
  if (action === 'approve')
    await API.approveComment(id);
  else
    await API.rejectComment(id);
  loadModeration();
}

// === Edit Profile ===
async function loadProfileEditor() {
  setPageMeta('Edit Profile');
  app.innerHTML = '<div class="loading">Loading profile...</div>';
  const r = await API.getUser(API.userId);

  let a = {};
  if (r.ok) a = r.data;

  app.innerHTML = `
    <h2>Edit Profile</h2>
    <form onsubmit="saveProfile(event)">
      <label for="p-name">Display Name</label>
      <input type="text" id="p-name" value="${esc(a.DisplayName || '')}" required>
      <label for="p-bio">Biography</label>
      <textarea id="p-bio" rows="4">${esc(a.Bio || '')}</textarea>
      <label for="p-url">Website</label>
      <input type="text" id="p-url" value="${esc(a.WebsiteUrl || '')}">
      <button type="submit">Save</button>
      <p id="p-msg" class="success hidden" style="margin-top:.5rem"></p>
    </form>
    <p style="margin-top:1rem"><a href="/dashboard">&laquo; Dashboard</a></p>
  `;
}

async function saveProfile(e) {
  e.preventDefault();
  const data = {
    DisplayName: $('#p-name').value,
    Bio: $('#p-bio').value,
    WebsiteUrl: $('#p-url').value
  };
  const r = await API.updateUser(API.userId, data);
  const msg = $('#p-msg');
  if (r.ok) {
    msg.textContent = 'Profile saved.';
    msg.className = 'success';
  } else {
    msg.textContent = 'Failed to save profile.';
    msg.className = 'error';
  }
}

// === Analytics ===
async function loadAnalytics() {
  setPageMeta('Analytics');
  app.innerHTML = '<div class="loading">Loading analytics...</div>';
  const r = await API.getOverview();
  if (!r.ok) { app.innerHTML = '<p class="error">Analytics service unavailable.</p>'; return; }

  const d = r.data;
  let html = '<h2>Analytics</h2>';

  // Overview cards
  html += '<div class="analytics-cards">';
  html += renderCard('Posts', d.Posts, d.PostsUnavailable);
  html += renderCard('Authors', d.Authors, d.AuthorsUnavailable);
  html += renderCard('Tags', d.Tags, d.TagsUnavailable);
  html += renderCard('Pending Comments', d.PendingComments, d.CommentsUnavailable);
  html += '</div>';

  // Sub-navigation
  html += `
    <div class="analytics-nav">
      <button onclick="navigate('/analytics/authors')">Author Stats</button>
      <button class="btn-outline" onclick="navigate('/analytics/tags')">Tag Cloud</button>
      <button class="btn-outline" onclick="navigate('/analytics/comments')">Comment Activity</button>
      <button class="btn-outline" onclick="navigate('/analytics/recent')">Recent Posts</button>
    </div>`;

  app.innerHTML = html;
}

function renderCard(label, value, unavailable) {
  if (unavailable)
    return `<div class="analytics-card unavailable"><div class="analytics-value">--</div><div class="analytics-label">${esc(label)}</div><div class="analytics-hint">Service unavailable</div></div>`;
  return `<div class="analytics-card"><div class="analytics-value">${value ?? 0}</div><div class="analytics-label">${esc(label)}</div></div>`;
}

async function loadAuthorStats() {
  setPageMeta('Author Stats');
  app.innerHTML = '<div class="loading">Loading author stats...</div>';
  const r = await API.getAuthorStats();
  if (!r.ok) { app.innerHTML = '<p class="error">Failed to load author stats.</p>'; return; }

  const authors = Array.isArray(r.data) ? r.data : [];
  let html = '<h2>Author Stats</h2>';
  if (authors.length === 0) {
    html += '<p>No author data available.</p>';
  } else {
    html += '<table class="analytics-table"><thead><tr><th>Author</th><th>Posts</th><th>Comments</th></tr></thead><tbody>';
    for (const a of authors) {
      html += `<tr>
        <td><a href="/authors/${a.AuthorId}">${esc(a.DisplayName)}</a></td>
        <td>${a.PostCount ?? 0}</td>
        <td>${a.CommentCount ?? 0}</td>
      </tr>`;
    }
    html += '</tbody></table>';
  }
  html += '<p style="margin-top:1rem"><a href="/analytics">&laquo; Analytics</a></p>';
  app.innerHTML = html;
}

async function loadTagCloudView() {
  setPageMeta('Tag Cloud');
  app.innerHTML = '<div class="loading">Loading tag cloud...</div>';
  const r = await API.getTagCloud();
  if (!r.ok) { app.innerHTML = '<p class="error">Failed to load tag cloud.</p>'; return; }

  const tags = Array.isArray(r.data) ? r.data : [];
  let html = '<h2>Tag Cloud</h2>';
  if (tags.length === 0) {
    html += '<p>No tags available.</p>';
  } else {
    const maxCount = Math.max(...tags.map(t => t.PostCount || 0), 1);
    html += '<div class="tag-cloud">';
    for (const t of tags) {
      const size = 0.8 + (t.PostCount || 0) / maxCount * 1.2;
      html += `<a class="tag-cloud-item" href="/tags/${t.TagId}" style="font-size:${size.toFixed(2)}rem">${esc(t.Name)} <sup>${t.PostCount || 0}</sup></a> `;
    }
    html += '</div>';
  }
  html += '<p style="margin-top:1rem"><a href="/analytics">&laquo; Analytics</a></p>';
  app.innerHTML = html;
}

async function loadCommentActivityView() {
  setPageMeta('Comment Activity');
  app.innerHTML = '<div class="loading">Loading comment activity...</div>';
  const r = await API.getCommentActivity();
  if (!r.ok) { app.innerHTML = '<p class="error">Failed to load comment activity.</p>'; return; }

  const d = r.data;
  let html = '<h2>Comment Activity</h2>';
  html += `<div class="analytics-cards">`;
  html += renderCard('Pending', d.PendingCount, false);
  html += `</div>`;

  const top = d.TopCommentedPosts || [];
  if (top.length > 0) {
    html += '<h3>Top Commented Posts</h3>';
    html += '<table class="analytics-table"><thead><tr><th>Post</th><th>Comments</th></tr></thead><tbody>';
    for (const p of top) {
      html += `<tr>
        <td><a href="/posts/${p.PostId}">${esc(p.Title)}</a></td>
        <td>${p.CommentCount ?? 0}</td>
      </tr>`;
    }
    html += '</tbody></table>';
  }
  html += '<p style="margin-top:1rem"><a href="/analytics">&laquo; Analytics</a></p>';
  app.innerHTML = html;
}

async function loadRecentPostsFullView() {
  setPageMeta('Recent Posts');
  app.innerHTML = '<div class="loading">Loading recent posts...</div>';
  const r = await API.getRecentPostsFull(10);
  if (!r.ok) { app.innerHTML = '<p class="error">Failed to load recent posts.</p>'; return; }

  const posts = Array.isArray(r.data) ? r.data : [];
  let html = '<h2>Recent Posts (Enriched)</h2>';
  if (posts.length === 0) {
    html += '<p>No posts available.</p>';
  } else {
    for (const p of posts) {
      const postId = p.ID;
      const date = p.PublishedAt ? new Date(p.PublishedAt).toLocaleDateString('en') : '';
      const tags = p.Tags || [];
      const comments = p.Comments || [];

      // Author block
      let authorHtml = '';
      if (p.Author && p.Author.DisplayName) {
        const a = p.Author;
        authorHtml = `<div class="enriched-author"><a href="/authors/${a.ID}">${esc(a.DisplayName)}</a>`;
        if (a.Bio) authorHtml += ` <span class="enriched-author-bio">&mdash; ${esc(a.Bio)}</span>`;
        authorHtml += '</div>';
      } else {
        authorHtml = '<div class="enriched-author">(Author unknown)</div>';
      }

      // Tags block
      let tagsHtml = '';
      if (p.TagsUnavailable) {
        tagsHtml = '<p class="error" style="margin:.3rem 0">Tags unavailable</p>';
      } else if (tags.length > 0) {
        tagsHtml = '<div class="enriched-tags">' + tags.map(t =>
          `<a class="tag" href="/tags/${t.ID}">${esc(t.Name)}</a>`
        ).join('') + '</div>';
      }

      // Comments block
      let commentsHtml = '';
      if (p.CommentsUnavailable) {
        commentsHtml = '<p class="error" style="margin:.3rem 0">Comments unavailable</p>';
      } else if (comments.length > 0) {
        commentsHtml = `<div class="enriched-comments"><strong>${comments.length} Comment(s):</strong>`;
        for (const c of comments) {
          const cDate = c.CreatedAt ? new Date(c.CreatedAt).toLocaleDateString('en') : '';
          commentsHtml += `
            <div class="comment">
              <span class="comment-author">${esc(c.AuthorName)}</span>
              <span class="comment-date">${cDate}</span>
              <div class="comment-body">${esc(c.Body)}</div>
            </div>`;
        }
        commentsHtml += '</div>';
      } else {
        commentsHtml = '<div class="enriched-comments"><em>No comments yet.</em></div>';
      }

      html += `
        <div class="post-card enriched-post">
          <h2><a href="/posts/${postId}">${esc(p.Title)}</a></h2>
          <div class="post-meta">${date}</div>
          ${authorHtml}
          ${tagsHtml}
          ${commentsHtml}
        </div>`;
    }
  }
  html += '<p style="margin-top:1rem"><a href="/analytics">&laquo; Analytics</a></p>';
  app.innerHTML = html;
}

// === Logs Viewer ===
const LOG_LEVEL_NAMES = {
  0: '', 1: 'NONE', 2: 'INFO', 3: 'DEBUG', 4: 'TRACE', 5: 'WARN',
  6: 'ERROR', 7: 'OSERR', 8: 'EXC', 9: 'EXCOS', 10: 'MEM', 11: 'STACK',
  12: 'FAIL', 13: 'SQL', 14: 'CACHE', 15: 'RES', 16: 'DB', 17: 'HTTP',
  18: 'CLI', 19: 'SVR', 20: 'SVCCALL', 21: 'SVCRET', 22: 'USER',
  23: 'CUSTOM1', 24: 'CUSTOM2', 25: 'CUSTOM3', 26: 'CUSTOM4', 27: 'NEW',
  28: 'DDD', 29: 'MON'
};

function logLevelClass(level) {
  if (level >= 6 && level <= 9) return 'log-error';
  if (level === 5) return 'log-warn';
  if (level === 2) return 'log-info';
  return 'log-other';
}

function formatTimestamp(ts) {
  if (!ts) return '';
  const d = new Date(ts);
  return d.toLocaleString('en') + '.' + String(d.getMilliseconds()).padStart(3, '0');
}

// Module-level handle to the active log stream so navigation away from /logs can close it.
let activeLogStream = null;

function closeActiveLogStream() {
  if (activeLogStream) {
    try { activeLogStream.close(); } catch (e) { /* ignore */ }
    activeLogStream = null;
  }
}

async function loadLogs() {
  closeActiveLogStream();
  setPageMeta('Logs');
  app.innerHTML = '<div class="loading">Loading logs...</div>';
  // Render the static page chrome (filters + results placeholder), then fire the initial query.
  app.innerHTML = `
    <h2>Central Logs</h2>
    <p style="color:var(--text-light)">
      Every log line from every service, shipped here in real time. Click any correlation ID to see the full
      cross-service trace for that request.
    </p>
    <div class="logs-filters">
      <input type="text" id="logs-search" placeholder="Full-text search (FTS5)..." style="flex:2">
      <select id="logs-service" style="flex:1">
        <option value="">All services</option>
        <option value="ms.gateway">ms.gateway</option>
        <option value="ms.auth">ms.auth</option>
        <option value="ms.users">ms.users</option>
        <option value="ms.posts">ms.posts</option>
        <option value="ms.tags">ms.tags</option>
        <option value="ms.comments">ms.comments</option>
        <option value="ms.media">ms.media</option>
        <option value="ms.analytics">ms.analytics</option>
        <option value="ms.config">ms.config</option>
        <option value="ms.logs">ms.logs</option>
      </select>
      <select id="logs-level" style="flex:1">
        <option value="0">All levels</option>
        <option value="2">Info+</option>
        <option value="5">Warn+</option>
        <option value="6">Error only</option>
      </select>
      <button onclick="refreshLogs()">Refresh</button>
    </div>
    <div id="logs-stats" class="logs-stats"></div>
    <div id="logs-results"><div class="loading">Loading...</div></div>
  `;
  $('#logs-search').addEventListener('keydown', e => {
    if (e.key === 'Enter') refreshLogs();
  });
  await loadLogsStats();
  await refreshLogs();
  // Open the live log stream so new entries pop in at the top of the table without polling.
  // The previous stream (if any) was closed at the start of loadLogs.
  activeLogStream = API.openLogStream(
    (entry) => prependLogEntry(entry),
    () => { /* onClose handled by api.js with auto-reconnect */ }
  );
}

/// Prepends one freshly arrived entry at the top of the logs table, fades it in, and trims
/// the table at 200 rows so the DOM stays light. Called from the WebSocket onmessage handler.
function prependLogEntry(entry) {
  const tbody = document.querySelector('#logs-results table tbody');
  if (!tbody) return;
  const lvl = LOG_LEVEL_NAMES[entry.Level] || String(entry.Level);
  const cls = logLevelClass(entry.Level);
  const corrLink = entry.CorrelationId
    ? `<a href="/logs/correlation/${encodeURIComponent(entry.CorrelationId)}" class="log-corr">${esc(entry.CorrelationId).substring(0, 8)}...</a>`
    : '';
  const tr = document.createElement('tr');
  tr.className = cls + ' log-new';
  tr.innerHTML = `
    <td class="log-ts">${formatTimestamp(entry.Timestamp)}</td>
    <td>${esc(entry.ServiceName)}</td>
    <td><span class="log-level">${lvl}</span></td>
    <td>${corrLink}</td>
    <td class="log-msg">${esc(entry.Message)}</td>`;
  tbody.insertBefore(tr, tbody.firstChild);
  // Trim the table at 200 rows.
  while (tbody.children.length > 200) {
    tbody.removeChild(tbody.lastChild);
  }
  // Remove the highlight class after the CSS animation runs.
  setTimeout(() => tr.classList.remove('log-new'), 1500);
}

async function loadLogsStats() {
  const r = await API.logsStats();
  const div = $('#logs-stats');
  if (!div) return;
  if (!r.ok || !r.data) {
    div.innerHTML = '<span class="error">Stats unavailable</span>';
    return;
  }
  const d = r.data;
  let html = `<strong>${d.TotalEntries ?? 0}</strong> total entries`;
  if (d.Services && d.Services.length > 0) {
    html += ' &mdash; ';
    html += d.Services.map(s => {
      let txt = `${esc(s.ServiceName)}: ${s.TotalCount}`;
      if (s.ErrorCount > 0) txt += ` <span class="log-error">(${s.ErrorCount} err)</span>`;
      else if (s.WarningCount > 0) txt += ` <span class="log-warn">(${s.WarningCount} wrn)</span>`;
      return txt;
    }).join(' &middot; ');
  }
  div.innerHTML = html;
}

async function refreshLogs() {
  const div = $('#logs-results');
  if (!div) return;
  div.innerHTML = '<div class="loading">Querying...</div>';
  const searchText = $('#logs-search').value.trim();
  const serviceName = $('#logs-service').value;
  const minLevel = parseInt($('#logs-level').value) || 0;
  let r;
  if (searchText) {
    r = await API.logsSearch(searchText, 200);
  } else {
    r = await API.logsRecent({
      ServiceName: serviceName,
      MinLevel: minLevel,
      Since: 0,
      UntilTime: 0,
      Limit: 200
    });
  }
  if (!r.ok) {
    div.innerHTML = '<p class="error">Failed to load logs.</p>';
    return;
  }
  const entries = Array.isArray(r.data) ? r.data : [];
  // Apply client-side service filter for FTS search results since the server-side filter only applies to Recent.
  const filtered = (searchText && serviceName)
    ? entries.filter(e => e.ServiceName === serviceName)
    : entries;
  renderLogEntries(filtered);
}

function renderLogEntries(entries) {
  const div = $('#logs-results');
  if (!div) return;
  if (entries.length === 0) {
    div.innerHTML = '<p style="color:var(--text-light)">No matching log entries.</p>';
    return;
  }
  let html = '<table class="logs-table"><thead><tr><th>Time</th><th>Service</th><th>Level</th><th>Correlation</th><th>Message</th></tr></thead><tbody>';
  for (const e of entries) {
    const lvl = LOG_LEVEL_NAMES[e.Level] || String(e.Level);
    const cls = logLevelClass(e.Level);
    const corrLink = e.CorrelationId
      ? `<a href="/logs/correlation/${encodeURIComponent(e.CorrelationId)}" class="log-corr">${esc(e.CorrelationId).substring(0, 8)}...</a>`
      : '';
    html += `<tr class="${cls}">
      <td class="log-ts">${formatTimestamp(e.Timestamp)}</td>
      <td>${esc(e.ServiceName)}</td>
      <td><span class="log-level">${lvl}</span></td>
      <td>${corrLink}</td>
      <td class="log-msg">${esc(e.Message)}</td>
    </tr>`;
  }
  html += '</tbody></table>';
  div.innerHTML = html;
}

async function loadLogsByCorrelation(corrId) {
  setPageMeta('Correlation Trace');
  app.innerHTML = '<div class="loading">Loading correlation trace...</div>';
  const r = await API.logsByCorrelationId(corrId);
  if (!r.ok) {
    app.innerHTML = '<p class="error">Failed to load trace.</p>';
    return;
  }
  const entries = Array.isArray(r.data) ? r.data : [];
  let html = `<h2>Correlation Trace</h2>
    <p>All entries with correlation ID <code>${esc(corrId)}</code> (${entries.length} entries)</p>`;
  if (entries.length === 0) {
    html += '<p>No entries found.</p>';
  } else {
    html += '<table class="logs-table"><thead><tr><th>Time</th><th>Service</th><th>Level</th><th>Message</th></tr></thead><tbody>';
    for (const e of entries) {
      const lvl = LOG_LEVEL_NAMES[e.Level] || String(e.Level);
      const cls = logLevelClass(e.Level);
      html += `<tr class="${cls}">
        <td class="log-ts">${formatTimestamp(e.Timestamp)}</td>
        <td>${esc(e.ServiceName)}</td>
        <td><span class="log-level">${lvl}</span></td>
        <td class="log-msg">${esc(e.Message)}</td>
      </tr>`;
    }
    html += '</tbody></table>';
  }
  html += '<p style="margin-top:1rem"><a href="/logs">&laquo; Back to logs</a></p>';
  app.innerHTML = html;
}

// === Utility Functions ===
function esc(str) {
  if (!str) return '';
  const div = document.createElement('div');
  div.textContent = String(str);
  return div.innerHTML;
}
