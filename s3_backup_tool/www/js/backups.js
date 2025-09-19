function renderBackups(json) {
  const tbody = document.querySelector('#backup-table tbody');
  const emptyState = document.getElementById('empty-state');
  if (!tbody) return;
  tbody.innerHTML = '';
  const list = (json && json.data && json.data.backups) || [];
  if (emptyState) emptyState.style.display = list.length ? 'none' : 'block';
  for (const backup of list) {
    const tr = document.createElement('tr');
    const sizeBytes = getBackupSizeBytes(backup);
    const date = backup.date || backup.created || '';
    tr.innerHTML = `
      <td><strong>${backup.name || 'Unbekannt'}</strong></td>
      <td><code>${backup.slug || ''}</code></td>
      <td>${formatDate(date)}</td>
      <td>${formatBytes(sizeBytes)}</td>
      <td><span class="backup-type">${backup.type || 'Vollständig'}</span></td>
      <td class="text-right">
        <div class="btn-group">
          <button class="btn btn-secondary btn-sm restore-btn" data-slug="${backup.slug}">Auswählen</button>
          <button class="btn btn-primary btn-sm upload-btn" data-slug="${backup.slug}">Hochladen</button>
        </div>
      </td>
    `;
    tbody.appendChild(tr);
  }

  tbody.querySelectorAll('.restore-btn').forEach(btn => {
    btn.onclick = () => {
      const slug = btn.getAttribute('data-slug');
      document.getElementById('slug').value = slug;
      document.querySelector('[data-tab="restore"]').click();
      populateRestoreOptionsFromBackup(slug);
      // Zeile visuell markieren
      const tr = btn.closest('tr');
      const table = tr?.closest('table');
      if (table) table.querySelectorAll('tbody tr').forEach(r => r.classList.remove('selected'));
      if (tr) tr.classList.add('selected');
      btn.textContent = '✓ Ausgewählt';
      setTimeout(() => { btn.textContent = 'Auswählen'; }, 1500);
    };
  });

  // Upload-Handler
  tbody.querySelectorAll('.upload-btn').forEach(btn => {
    btn.onclick = async () => {
      const slug = btn.getAttribute('data-slug');
      out(`Lade Backup ${slug} zu S3 hoch...`);
      setLoading(true);
      btn.disabled = true;
      const original = btn.textContent;
      btn.textContent = 'Lädt...';
      try {
        const res = await call('api/upload', { body: JSON.stringify({ slug }) });
        if (res.ok) {
          try { const j = JSON.parse(res.body || '{}'); if (j.s3_key) out(`Upload abgeschlossen: s3://${j.s3_key}`); } catch (_) {}
          out('Upload erfolgreich');
          // S3-Liste aktualisieren
          try { const s3Result = await call('api/list-s3'); if (s3Result.ok) renderS3List(JSON.parse(s3Result.body)); } catch (_) {}
        } else {
          out('Upload fehlgeschlagen');
        }
      } catch (e) {
        out('Fehler beim Upload: ' + e.message);
      } finally {
        btn.disabled = false;
        btn.textContent = original;
        setLoading(false);
      }
    };
  });

}

function renderS3List(json) {
  const tbody = document.querySelector('#s3-table tbody');
  const emptyState = document.getElementById('s3-empty');
  if (!tbody) return;
  tbody.innerHTML = '';
  const list = (json && json.objects) || [];
  if (emptyState) emptyState.style.display = list.length ? 'none' : 'block';
  for (const obj of list) {
    const tr = document.createElement('tr');
    const size = obj.Size || obj.size || '';
    const lastModified = obj.LastModified || obj.lastModified || '';
    const key = obj.Key || obj.key || '';
    tr.innerHTML = `
      <td><code>${key}</code></td>
      <td>${formatSize(size)}</td>
      <td>${formatDate(lastModified)}</td>
      <td class="text-right">
        <button class="btn btn-secondary btn-sm pick-s3-btn" data-key="${key}">Auswählen</button>
      </td>
    `;
    tbody.appendChild(tr);
  }
  tbody.querySelectorAll('.pick-s3-btn').forEach(btn => {
    btn.onclick = () => {
      const key = btn.getAttribute('data-key');
      document.getElementById('s3key').value = key;
      // Zeile visuell markieren
      const tr = btn.closest('tr');
      const table = tr?.closest('table');
      if (table) table.querySelectorAll('tbody tr').forEach(r => r.classList.remove('selected'));
      if (tr) tr.classList.add('selected');
      btn.textContent = '✓ Ausgewählt';
      setTimeout(() => btn.textContent = 'Auswählen', 1500);
    };
  });
}


function initializeBackupCreationForm() {
  const fullCb = document.getElementById('nb-full');
  const addonsBox = document.getElementById('nb-addons');
  const foldersBox = document.getElementById('nb-folders');
  const includeHaCb = document.getElementById('nb-include-ha');
  const createBtn = document.getElementById('btn-nb-create');

  // Addons laden
  (async () => {
    try {
      const res = await call('api/addons');
      if (res.ok) {
        const j = JSON.parse(res.body || '{}');
        const list = Array.isArray(j.addons) ? j.addons : [];
        addonsBox.innerHTML = '';
        if (!list.length) { addonsBox.innerHTML = '<div class="text-muted">Keine Add-ons gefunden.</div>'; }
        list.forEach(a => {
          const id = `nb-addon-${a.slug}`;
          const label = document.createElement('label');
          label.className = 'checkbox-label';
          label.innerHTML = `<input type="checkbox" class="form-checkbox" data-addon="${a.slug}" id="${id}" /><span class="checkbox-indicator"></span> ${a.name}`;
          addonsBox.appendChild(label);
        });
      }
    } catch (_) {}
  })();

  const updateVisibility = () => {
    const isFull = !!fullCb?.checked;
    [addonsBox, foldersBox, includeHaCb?.parentElement?.parentElement].forEach(el => { if (!el) return; el.style.opacity = isFull ? '0.4' : '1'; el.style.pointerEvents = isFull ? 'none' : 'auto'; });
  };
  if (fullCb) fullCb.onchange = updateVisibility; updateVisibility();

  // Profil-Vorbelegung
  const profileSelect = document.getElementById('nb-profile');
  const applyProfile = (p) => {
    if (!p) return;
    const isFull = p.full === true;
    if (fullCb) fullCb.checked = !!isFull;
    document.getElementById('nb-name').value = p.name || '';
    document.getElementById('nb-password').value = p.password || '';
    const setChecks = (selector, keys, attr) => {
      const set = new Set(keys || []);
      document.querySelectorAll(selector).forEach(el => { el.checked = set.has(el.getAttribute(attr)); });
    };
    document.getElementById('nb-include-ha').checked = !!p.homeassistant;
    setChecks('#nb-folders [data-folder]', p.folders, 'data-folder');
    setChecks('#nb-addons [data-addon]', p.addons, 'data-addon');
    updateVisibility();
  };
  if (profileSelect) profileSelect.onchange = () => {
    try { const p = JSON.parse(profileSelect.value || '{}'); applyProfile(p); } catch (_) {}
  };

  if (createBtn) createBtn.onclick = async () => {
    const isFull = !!fullCb?.checked;
    const name = document.getElementById('nb-name')?.value || '';
    const password = document.getElementById('nb-password')?.value || '';
    const includeHa = !!document.getElementById('nb-include-ha')?.checked;
    const folders = Array.from(document.querySelectorAll('#nb-folders [data-folder]:checked')).map(el => el.getAttribute('data-folder'));
    const addons = Array.from(document.querySelectorAll('#nb-addons [data-addon]:checked')).map(el => el.getAttribute('data-addon'));
    const uploadAfter = !!document.getElementById('nb-upload-after')?.checked;
    const payload = { name, password: password || null, full: isFull };
    if (!isFull) {
      payload.homeassistant = includeHa;
      payload.folders = folders;
      payload.addons = addons;
    }
    setLoading(true);
    out('Erstelle neues Backup...');
    try {
      const res = await call('api/create-backup', { body: JSON.stringify(payload) });
      if (res.ok) {
        out('Backup erstellt');
        // Optionaler Upload: hole Slug aus /api/list
        if (uploadAfter) {
          try {
            const listRes = await call('api/list');
            const j = JSON.parse(listRes.body || '{}');
            const backups = (j && j.data && j.data.backups) || [];
            const newest = backups.sort((a,b)=> new Date(b.date||b.created||0)-new Date(a.date||a.created||0))[0];
            if (newest && newest.slug) {
              out('Lade neues Backup zu S3 hoch...');
              const up = await call('api/upload', { body: JSON.stringify({ slug: newest.slug }) });
              if (up.ok) { try { const uj = JSON.parse(up.body||'{}'); if (uj.s3_key) out(`Uploaded: s3://${uj.s3_key}`); } catch(_){} }
            }
          } catch (_) {}
        }
        refresh();
      } else {
        out('Backup erstellen fehlgeschlagen');
      }
    } catch (e) {
      out('Fehler: ' + e.message);
    } finally {
      setLoading(false);
    }
  };
}


