async function call(path, opts={}){
  const res = await fetch(path, {method:'POST', headers:{'Content-Type':'application/json'}, ...opts});
  const txt = await res.text();
  return {ok: res.ok, body: txt};
}

function out(msg){
  const el = document.getElementById('output');
  el.textContent = (el.textContent + "\n" + msg).trim();
}

function setLoading(isLoading){
  document.getElementById('spinner').classList.toggle('hidden', !isLoading);
}

function renderBackups(json){
  const t = document.querySelector('#backup-table tbody');
  t.innerHTML = '';
  const list = (json && json.data && json.data.backups) || [];
  document.getElementById('empty-state').style.display = list.length? 'none':'block';
  for(const b of list){
    const tr = document.createElement('tr');
    const size = b.size || b.size_in_bytes || '';
    const date = b.date || b.created || '';
    tr.innerHTML = `
      <td>${b.name || ''}</td>
      <td>${b.slug || ''}</td>
      <td>${date}</td>
      <td>${size}</td>
      <td>${b.type || ''}</td>
      <td><button data-slug="${b.slug}" class="restore">Restore</button></td>
    `;
    t.appendChild(tr);
  }
  t.querySelectorAll('button.restore').forEach(btn=>{
    btn.onclick = ()=>{
      document.getElementById('slug').value = btn.getAttribute('data-slug');
    }
  });
}

document.getElementById('btn-backup').onclick = async ()=>{
  out('Starting backup...');
  setLoading(true);
  const r = await call('/api/backup');
  setLoading(false);
  out(r.body || (r.ok?'OK':'Error'));
}

async function refresh(){
  out('Listing backups...');
  setLoading(true);
  const r = await call('/api/list');
  setLoading(false);
  try { renderBackups(JSON.parse(r.body)); } catch(e){ /* ignore */ }
  out(r.body || (r.ok?'OK':'Error'));
}

document.getElementById('btn-refresh').onclick = refresh;

document.getElementById('btn-restore-local').onclick = async ()=>{
  const slug = document.getElementById('slug').value.trim();
  if(!slug){ out('Please enter a slug'); return; }
  out('Restoring (local slug)...');
  setLoading(true);
  const r = await call('/api/restore-local', {body: JSON.stringify({slug})});
  setLoading(false);
  out(r.body || (r.ok?'OK':'Error'));
}

document.getElementById('btn-restore-s3').onclick = async ()=>{
  const s3key = document.getElementById('s3key').value.trim();
  if(!s3key){ out('Please enter an S3 key'); return; }
  out('Restoring (from S3)...');
  setLoading(true);
  const r = await call('/api/restore-s3', {body: JSON.stringify({key: s3key})});
  setLoading(false);
  out(r.body || (r.ok?'OK':'Error'));
}

// initial load
refresh().catch(()=>{});

