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

let selectedPreset = null;
document.querySelectorAll('button.preset').forEach(btn=>{
  btn.onclick = ()=>{
    document.querySelectorAll('button.preset').forEach(b=>b.classList.remove('primary'));
    btn.classList.add('primary');
    selectedPreset = { ep: btn.dataset.ep, rg: btn.dataset.rg, fps: btn.dataset.fps };
    const rs = document.getElementById('region-select');
    const ep = document.getElementById('endpoint-input');
    const fps = document.getElementById('fps-input');
    if(selectedPreset.rg && selectedPreset.rg !== 'auto'){ rs.value = selectedPreset.rg; }
    if(selectedPreset.ep){ ep.value = selectedPreset.ep; }
    fps.checked = (selectedPreset.fps === 'true');
  }
});

document.getElementById('btn-apply-preset').onclick = async ()=>{
  const rs = document.getElementById('region-select');
  const ep = document.getElementById('endpoint-input');
  const fps = document.getElementById('fps-input');
  const region = (rs && rs.value) || (selectedPreset && selectedPreset.rg) || 'us-east-1';
  const endpoint = (ep && ep.value) || (selectedPreset && selectedPreset.ep) || '';
  const pathStyle = (fps && fps.checked) || (selectedPreset && selectedPreset.fps === 'true') || false;
  out('Applying provider preset...');
  setLoading(true);
  const r = await call('/api/set-overrides', {body: JSON.stringify({
    s3_endpoint_url: endpoint,
    s3_region_name: region,
    force_path_style: pathStyle
  })});
  setLoading(false);
  out(r.body || (r.ok?'OK':'Error'));
}

document.getElementById('btn-apply-credentials').onclick = async ()=>{
  const bkt = document.getElementById('bucket-input').value.trim();
  const ak = document.getElementById('ak-input').value.trim();
  const sk = document.getElementById('sk-input').value.trim();
  if(!bkt || !ak || !sk){ out('Please enter bucket, access key and secret'); return; }
  out('Applying credentials...');
  setLoading(true);
  const r = await call('/api/set-overrides', {body: JSON.stringify({
    s3_bucket: bkt,
    access_key_id: ak,
    secret_access_key: sk
  })});
  setLoading(false);
  out(r.body || (r.ok?'OK':'Error'));
}

