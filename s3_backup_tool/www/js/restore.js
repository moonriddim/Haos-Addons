async function populateRestoreOptionsFromBackup(slug) {
  try {
    const res = await call('api/backup-info', { body: JSON.stringify({ slug }) });
    if (!res.ok) return;
    const info = JSON.parse(res.body);
    const data = info.data || {};
    const placeholder = document.getElementById('restore-placeholder');
    const selection = document.getElementById('restore-selection');
    if (placeholder) placeholder.classList.add('hidden');
    if (selection) selection.classList.remove('hidden');
    const ha = document.getElementById('restore-ha');
    if (ha && typeof data.homeassistant === 'boolean') {
      ha.checked = data.homeassistant;
    }
    const foldersList = document.getElementById('folders-list');
    if (foldersList) {
      foldersList.innerHTML = '';
      const folders = Array.isArray(data.folders) ? data.folders : [];
      if (!folders.length) {
        foldersList.innerHTML = '<div class="text-muted">Keine Ordner im Backup gefunden.</div>';
      } else {
        folders.forEach(f => {
          const lbl = document.createElement('label');
          lbl.className = 'checkbox-label';
          const name = ({
            homeassistant: 'Einstellungen und Verlauf',
            media: 'Medien',
            ssl: 'SSL-Zertifikate',
            share: 'Share-Ordner'
          })[f] || f;
          lbl.innerHTML = `<input type="checkbox" value="${f}" class="form-checkbox restore-folder"> <span class="checkbox-indicator"></span> ${name}`;
          foldersList.appendChild(lbl);
        });
      }
    }
    const addonsListEl = document.getElementById('addons-list');
    if (addonsListEl) {
      addonsListEl.innerHTML = '';
      const addons = Array.isArray(data.addons) ? data.addons : [];
      if (!addons.length) {
        addonsListEl.innerHTML = '<div class="text-muted">Keine Add-ons im Backup gefunden.</div>';
      } else {
        addons.forEach(a => {
          const slugVal = a.slug || a;
          const nameVal = a.name || slugVal;
          const div = document.createElement('label');
          div.className = 'checkbox-label';
          div.innerHTML = `<input type="checkbox" class="form-checkbox restore-addon" value="${slugVal}"> <span class="checkbox-indicator"></span> ${nameVal}`;
          addonsListEl.appendChild(div);
        });
      }
    }
  } catch (_) {}
}

async function restoreLocal() {
  const slug = document.getElementById('slug').value.trim();
  if (!slug) { out('Fehler: Backup-Slug ist erforderlich'); return; }
  await restoreLocalWithSlug(slug);
}

async function restoreLocalWithSlug(slug) {
  out(`Stelle lokales Backup wieder her: ${slug}`);
  setLoading(true);
  try {
    let includeHA = document.getElementById('restore-ha')?.checked;
    let folders = Array.from(document.querySelectorAll('.restore-folder:checked')).map(el => el.value);
    let addons = Array.from(document.querySelectorAll('.restore-addon:checked')).map(el => el.value);
    if (folders.length === 0 && addons.length === 0) {
      const infoRes = await call('api/backup-info', { body: JSON.stringify({ slug }) });
      if (infoRes.ok) {
        const info = JSON.parse(infoRes.body);
        const data = info.data || {};
        if (typeof includeHA !== 'boolean' && typeof data.homeassistant === 'boolean') includeHA = data.homeassistant;
        if (Array.isArray(data.folders)) folders = data.folders;
        if (Array.isArray(data.addons)) addons = data.addons.map(a => (a.slug || a));
      }
    }
    const payload = { slug };
    if (typeof includeHA === 'boolean') payload.homeassistant = includeHA;
    if (folders.length) payload.folders = folders;
    if (addons.length) payload.addons = addons;
    const result = await call('api/restore-local', { body: JSON.stringify(payload) });
    out(result.body || (result.ok ? 'Lokales Backup erfolgreich wiederhergestellt!' : 'Fehler bei der Wiederherstellung'));
  } catch (error) {
    out(`Fehler: ${error.message}`);
  } finally {
    setLoading(false);
  }
}

async function restoreFromS3() {
  const s3key = document.getElementById('s3key').value.trim();
  if (!s3key) { out('Fehler: S3-Schlüssel ist erforderlich'); return; }
  out(`Stelle Cloud-Backup wieder her: ${s3key}`);
  setLoading(true);
  try {
    const result = await call('api/restore-s3', { body: JSON.stringify({ key: s3key }) });
    out(result.body || (result.ok ? 'Cloud-Backup erfolgreich wiederhergestellt!' : 'Fehler bei der Wiederherstellung'));
  } catch (error) {
    out(`Fehler: ${error.message}`);
  } finally {
    setLoading(false);
  }
}


