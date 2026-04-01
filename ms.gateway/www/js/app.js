/**
 * Blog SPA -- Vanilla JavaScript.
 * Routing, rendering and event handling.
 */

const $ = (sel) => document.querySelector(sel);
const $$ = (sel) => document.querySelectorAll(sel);
const app = $('#app');

// === Initialization ===
document.addEventListener('DOMContentLoaded', () => {
  updateAuthNav();
  loadPosts();
});

function updateAuthNav() {
  const nav = $('#auth-nav');
  if (API.isLoggedIn()) {
    nav.innerHTML = `
      <a href="#" onclick="loadDashboard(); return false;">Dashboard</a>
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
  app.innerHTML = '<div class="loading">Loading posts...</div>';
  const r = await API.getPosts(page);
  if (!r.ok) { app.innerHTML = '<p class="error">Failed to load posts.</p>'; return; }

  const posts = r.data.items || r.data || [];
  const total = r.data.total || 0;
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
        <h2><a href="#" onclick="loadPost(${p.RowID || p.ID}); return false;">${esc(p.Title)}</a></h2>
        <div class="post-meta">${date}</div>
        <p class="post-excerpt">${esc(p.Excerpt || '')}</p>
      </li>`;
  }
  html += '</ul>';

  if (totalPages > 1) {
    html += '<div class="pagination">';
    if (page > 1)
      html += `<button class="btn-outline btn-sm" onclick="loadPosts(${page - 1})">&laquo; Previous</button>`;
    html += `<span style="padding:.5rem">Page ${page} / ${totalPages}</span>`;
    if (page < totalPages)
      html += `<button class="btn-outline btn-sm" onclick="loadPosts(${page + 1})">Next &raquo;</button>`;
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
  const postId = p.RowID || p.ID || id;
  const date = p.PublishedAt ? new Date(p.PublishedAt).toLocaleDateString('en') : '';
  const author = p.Author || {};
  const tags = p.Tags || [];
  const comments = p.Comments || [];

  let tagsHtml = tags.map(t => `<span class="tag">${esc(t.Name || '')}</span>`).join('');

  let commentsHtml = '';
  for (const c of comments) {
    const cDate = c.CreatedAt ? new Date(c.CreatedAt).toLocaleDateString('en') : '';
    commentsHtml += `
      <div class="comment">
        <span class="comment-author">${esc(c.AuthorName)}</span>
        <span class="comment-date">${cDate}</span>
        <div class="comment-body">${esc(c.Body)}</div>
      </div>`;
  }

  app.innerHTML = `
    <article class="post-full">
      <h1>${esc(p.Title)}</h1>
      <div class="post-meta">
        ${date}
        ${author.DisplayName ? ' &mdash; <a href="#" onclick="loadAuthor(' + (author.RowID || author.ID) + '); return false;">' + esc(author.DisplayName) + '</a>' : ''}
      </div>
      ${tagsHtml ? '<div style="margin:.5rem 0">' + tagsHtml + '</div>' : ''}
      <div class="post-body">${esc(p.Body)}</div>
    </article>

    <section class="comments-section">
      <h3>Comments (${comments.length})</h3>
      ${commentsHtml || '<p style="color:var(--text-light)">No comments yet.</p>'}

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
      </div>
    </section>

    <p style="margin-top:2rem"><a href="#" onclick="loadPosts(); return false;">&laquo; Back to overview</a></p>
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
    html += `<li><span class="tag" onclick="loadPostsByTag(${t.RowID || t.ID}, '${esc(t.Name)}')">${esc(t.Name)}</span></li>`;
  html += '</ul>';
  app.innerHTML = html;
}

async function loadPostsByTag(tagId, tagName) {
  app.innerHTML = `<div class="loading">Loading posts tagged "${esc(tagName)}"...</div>`;
  const r = await API.get(`/api/tags/${tagId}/posts`);
  if (!r.ok) { app.innerHTML = '<p class="error">Error.</p>'; return; }

  const postIds = Array.isArray(r.data) ? r.data : [];
  let html = `<h2>Tag: ${esc(tagName)}</h2>`;
  if (postIds.length === 0) {
    html += '<p>No posts with this tag.</p>';
  } else {
    html += '<ul class="post-list">';
    for (const item of postIds) {
      const pid = item.PostId || item;
      const pr = await API.getPost(pid);
      if (pr.ok) {
        const p = pr.data;
        html += `
          <li class="post-card">
            <h2><a href="#" onclick="loadPost(${p.RowID || p.ID}); return false;">${esc(p.Title)}</a></h2>
            <p class="post-excerpt">${esc(p.Excerpt || '')}</p>
          </li>`;
      }
    }
    html += '</ul>';
  }
  html += '<p><a href="#" onclick="loadTags(); return false;">&laquo; All Tags</a></p>';
  app.innerHTML = html;
}

// === Author Profile ===
async function loadAuthor(id) {
  app.innerHTML = '<div class="loading">Loading profile...</div>';
  const r = await API.getUser(id);
  if (!r.ok) { app.innerHTML = '<p class="error">Author not found.</p>'; return; }

  const a = r.data;
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
    <p style="margin-top:1rem"><a href="#" onclick="loadPosts(); return false;">&laquo; Back</a></p>
  `;

  const pr = await API.get(`/api/posts/by-author/${id}`);
  const postsDiv = $('#author-posts');
  if (pr.ok && pr.data.items && pr.data.items.length > 0) {
    let ph = '<ul class="post-list">';
    for (const p of pr.data.items)
      ph += `<li class="post-card"><h2><a href="#" onclick="loadPost(${p.RowID || p.ID}); return false;">${esc(p.Title)}</a></h2></li>`;
    ph += '</ul>';
    postsDiv.innerHTML = ph;
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
      loadDashboard();
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
  loadPosts();
}

// === Dashboard (authenticated) ===
async function loadDashboard() {
  if (!API.isLoggedIn()) { showLogin(); return; }

  app.innerHTML = '<div class="loading">Loading dashboard...</div>';

  let html = `
    <h2>Dashboard</h2>
    <div class="dashboard-actions">
      <button onclick="clearEditor(); showEditor()">New Post</button>
      <button class="btn-outline" onclick="loadModeration()">Comment Moderation</button>
      <button class="btn-outline" onclick="loadProfileEditor()">Edit Profile</button>
    </div>
    <h3>My Posts</h3>
  `;

  const r = await API.getMyPosts();
  if (r.ok) {
    const posts = r.data.items || r.data || [];
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
                <button class="btn-sm btn-outline" onclick="editPost(${p.RowID || p.ID})">Edit</button>
                <button class="btn-sm btn-danger" onclick="deletePostConfirm(${p.RowID || p.ID})">Delete</button>
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
    const tid = t.RowID || t.ID;
    const checked = selectedIds.includes(tid) ? ' checked' : '';
    return `<label class="tag-checkbox"><input type="checkbox" value="${tid}"${checked}> ${esc(t.Name)}</label>`;
  }).join('');
  $('#editor-new-tag').value = '';
}

async function addNewTag() {
  const input = $('#editor-new-tag');
  const name = input.value.trim();
  if (!name) return;
  const r = await API.post('/api/tags', { Name: name, Description: '' });
  if (r.ok) {
    const newId = r.data.id;
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
  const postTags = (p.Tags || []).map(t => t.RowID || t.ID);
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
    const postId = id || r.data?.id;
    if (postId) {
      const tagIds = getSelectedTagIds();
      await API.setPostTags(postId, tagIds);
    }
    hideEditor();
    loadDashboard();
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
            <button class="btn-sm btn-success" onclick="moderateComment(${c.RowID || c.ID}, 'approve')">Approve</button>
            <button class="btn-sm btn-danger" onclick="moderateComment(${c.RowID || c.ID}, 'reject')">Reject</button>
          </div>
        </div>`;
    }
  }
  html += '<p style="margin-top:1rem"><a href="#" onclick="loadDashboard(); return false;">&laquo; Dashboard</a></p>';
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
    <p style="margin-top:1rem"><a href="#" onclick="loadDashboard(); return false;">&laquo; Dashboard</a></p>
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

// === Utility Functions ===
function esc(str) {
  if (!str) return '';
  const div = document.createElement('div');
  div.textContent = String(str);
  return div.innerHTML;
}
