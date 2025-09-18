function initializeProviders() {
  const providerCards = document.querySelectorAll('.provider-card');
  const capsByProvider = {
    aws:     { sse: ['AES256','KMS'], kms: true,  versioning: true,  pathStyle: false, region: true,  endpoint: true },
    gcp:     { sse: ['AES256','KMS'], kms: true,  versioning: true,  pathStyle: false, region: true,  endpoint: true },
    hetzner: { sse: ['AES256'],       kms: false, versioning: true,  pathStyle: false, region: false, endpoint: true },
    storj:   { sse: [],               kms: false, versioning: false, pathStyle: false, region: false, endpoint: true }
  };

  // Regionen pro Provider (kuratiert)
  const regionsByProvider = {
    aws: [
      'us-east-1','us-east-2','us-west-1','us-west-2',
      'ca-central-1','sa-east-1','eu-west-1','eu-west-2','eu-west-3','eu-north-1','eu-south-1','eu-south-2','eu-central-1','eu-central-2',
      'me-south-1','me-central-1','af-south-1',
      'ap-south-1','ap-south-2','ap-southeast-1','ap-southeast-2','ap-southeast-3','ap-southeast-4','ap-northeast-1','ap-northeast-2','ap-northeast-3','ap-east-1',
      'il-central-1'
    ],
    gcp: [
      'us-central1','us-east1','us-east4','us-west1','us-west2','us-west3','us-west4','northamerica-northeast1','southamerica-east1',
      'europe-west1','europe-west2','europe-west3','europe-west4','europe-west6','europe-central2','europe-north1',
      'asia-east1','asia-east2','asia-northeast1','asia-northeast2','asia-northeast3','asia-south1','asia-south2','asia-southeast1','asia-southeast2',
      'australia-southeast1','australia-southeast2'
    ],
    hetzner: ['fsn1','nbg1','hel1','ash'],
  };

  function applyCapabilityUI(provider) {
    const caps = capsByProvider[provider] || capsByProvider.aws;
    const show = (id, visible) => {
      const el = document.getElementById(id);
      if (!el) return;
      el.style.display = visible ? '' : 'none';
    };
    // Endpoint und Region
    show('group-endpoint', caps.endpoint !== false);
    show('group-region',   caps.region   !== false);
    // Regionenliste dynamisch füllen, wenn unterstützt
    const regionSelect = document.getElementById('region-select');
    const regionInput  = document.getElementById('region-input');
    if (caps.region && regionSelect && regionInput) {
      const list = regionsByProvider[provider] || [];
      // Kopfzeile
      regionSelect.innerHTML = '<option value="">Häufig verwendete Regionen</option>' + (list.map(r => `<option value="${r}">${r}</option>`).join(''));
      // Default vorbelegen, wenn Nutzer nicht editiert hat
      if (!regionDirty) {
        const preferred = (selectedPreset && selectedPreset.rg) || (list && list[0]) || '';
        regionInput.value = preferred;
        regionSelect.value = preferred && list.includes(preferred) ? preferred : '';
      }
    }
    show('group-fps',      !!caps.pathStyle);
    // SSE und KMS
    const sseGroup = document.getElementById('group-sse');
    const sseSelect = document.getElementById('sse-select');
    if (sseGroup && sseSelect) {
      if (!caps.sse || caps.sse.length === 0) {
        sseGroup.style.display = 'none';
      } else {
        sseGroup.style.display = '';
        sseSelect.innerHTML = '<option value="">Keine</option>' +
          (caps.sse.includes('AES256') ? '<option value="AES256">AES256 (S3-Managed Keys)</option>' : '') +
          (caps.sse.includes('KMS')    ? '<option value="KMS">AWS KMS (kundenverwalteter Schlüssel)</option>' : '');
      }
    }
    show('group-kms', !!caps.kms);
    show('group-versioning', !!caps.versioning);

    // Provider-spezifischer Hinweis (z. B. Storj ohne Versionierung/SSE)
    const note = document.getElementById('provider-note');
    if (note) {
      if (provider === 'storj') {
        note.textContent = 'Storj nutzt clientseitige Ende-zu-Ende-Verschlüsselung und bietet keine native Objekt-Versionierung.';
      } else if (provider === 'hetzner') {
        note.textContent = 'Hetzner unterstützt Versionierung und SSE (AES256).';
      } else if (provider === 'gcp') {
        note.textContent = 'Google Cloud: Objektversionierung und Verschlüsselung (inkl. kundenverwaltete Schlüssel) verfügbar.';
      } else if (provider === 'aws') {
        note.textContent = 'AWS S3: Versionierung, SSE (AES256/KMS) und Regionen-Auswahl verfügbar.';
      } else {
        note.textContent = '';
      }
    }
  }
  providerCards.forEach(card => {
    card.onclick = () => {
      providerCards.forEach(c => c.classList.remove('active'));
      card.classList.add('active');
      selectedPreset = { ep: card.dataset.ep, rg: card.dataset.rg, fps: card.dataset.fps, id: card.dataset.provider };
      applyCapabilityUI(selectedPreset.id);
      const regionInput = document.getElementById('region-input');
      const regionSelect = document.getElementById('region-select');
      const endpointInput = document.getElementById('endpoint-input');
      const pathStyleCheckbox = document.getElementById('fps-input');
      if (selectedPreset.rg && selectedPreset.rg !== 'auto' && !regionDirty) {
        regionInput.value = selectedPreset.rg; regionSelect.value = selectedPreset.rg;
      }
      if (selectedPreset.ep && !endpointDirty) { endpointInput.value = selectedPreset.ep; }
      pathStyleCheckbox.checked = selectedPreset.fps === 'true';
      out(`Provider ausgewählt: ${card.querySelector('.provider-name').textContent}`);
    };
  });

  // Backup-Einstellungen speichern
  const btnApplyBackup = document.getElementById('btn-apply-backup');
  if (btnApplyBackup) {
    btnApplyBackup.onclick = async () => {
      const payload = {
        watch_ha_backups: !!document.getElementById('watch-ha-input')?.checked,
        upload_existing: !!document.getElementById('upload-existing-input')?.checked,
        delete_local_after_upload: !!document.getElementById('delete-local-input')?.checked,
        run_on_start: !!document.getElementById('run-on-start-input')?.checked,
        backup_interval_hours: document.getElementById('interval-input')?.value || null,
        backup_schedule_cron: document.getElementById('cron-input')?.value || null,
        retention_keep_last_s3: document.getElementById('keep-last-input')?.value || null,
        retention_days_s3: document.getElementById('retention-days-input')?.value || null,
      };
      setLoading(true);
      try {
        const result = await call('api/set-overrides', { body: JSON.stringify(payload) });
        out(result.body || (result.ok ? 'Backup Einstellungen gespeichert' : 'Fehler beim Speichern'));
      } catch (e) {
        out('Fehler: ' + e.message);
      } finally {
        setLoading(false);
      }
    };
  }

  const regionInput = document.getElementById('region-input');
  const regionSelect = document.getElementById('region-select');
  const endpointInput = document.getElementById('endpoint-input');
  const prefixInput = document.getElementById('prefix-input');
  // Beim Initialisieren Standard-Provider anwenden, falls aktiv markiert
  const active = document.querySelector('.provider-card.active');
  if (active) {
    selectedPreset = { ep: active.dataset.ep, rg: active.dataset.rg, fps: active.dataset.fps, id: active.dataset.provider };
    applyCapabilityUI(selectedPreset.id);
  }

  // Summary anzeigen
  function loadSummaryFromOverrides() {
    const bucket = document.getElementById('bucket-input')?.value || '—';
    const prefix = document.getElementById('prefix-input')?.value || '—';
    const endpoint = document.getElementById('endpoint-input')?.value || '—';
    const activeId = document.querySelector('.provider-card.active')?.dataset.provider || (selectedPreset && selectedPreset.id) || 'aws';
    const caps = (typeof capsByProvider !== 'undefined' ? capsByProvider[activeId] : null) || {};
    const region = caps.region ? (document.getElementById('region-input')?.value || '—') : '—';
    const sse = (Array.isArray(caps.sse) && caps.sse.length > 0) ? (document.getElementById('sse-select')?.value || '—') : '—';
    const versioning = caps.versioning ? (document.getElementById('versioning-input')?.checked ? 'aktiv' : 'aus') : '—';
    const set = (id, val) => { const el = document.getElementById(id); if (el) el.textContent = val || '—'; };
    set('sum-bucket', bucket);
    set('sum-prefix', prefix);
    set('sum-endpoint', endpoint);
    set('sum-region', region);
    set('sum-sse', sse || '—');
    set('sum-versioning', versioning);
  }

  const summaryCard = document.getElementById('provider-summary-card');
  const editWrapper = document.getElementById('provider-edit-wrapper');
  const btnEdit = document.getElementById('btn-edit-provider');
  const btnCancel = document.getElementById('btn-cancel-edit');
  if (btnEdit && summaryCard && editWrapper) {
    btnEdit.onclick = () => { editWrapper.style.display = ''; summaryCard.style.display = 'none'; };
    if (btnCancel) btnCancel.onclick = () => { editWrapper.style.display = 'none'; summaryCard.style.display = ''; loadSummaryFromOverrides(); };
    // Initial anzeigen
    loadSummaryFromOverrides();
  }

  // Service-Buttons (Start/Stop/Status)
  const btnStart = document.getElementById('btn-service-start');
  const btnStop = document.getElementById('btn-service-stop');
  const statusEl = document.getElementById('service-status');
  async function refreshServiceStatus() {
    try {
      const res = await call('api/service', { body: JSON.stringify({ cmd: 'status' }) });
      if (res.ok) {
        const j = JSON.parse(res.body || '{}');
        if (statusEl) statusEl.textContent = j.status || 'UNKNOWN';
      }
    } catch (_) {}
  }
  if (btnStart) btnStart.onclick = async () => { await call('api/service', { body: JSON.stringify({ cmd: 'start' }) }); setTimeout(refreshServiceStatus, 500); };
  if (btnStop) btnStop.onclick = async () => { await call('api/service', { body: JSON.stringify({ cmd: 'stop' }) }); setTimeout(refreshServiceStatus, 500); };
  setTimeout(refreshServiceStatus, 300);

  const btnSaveClose = document.getElementById('btn-save-close');
  const btnClearCreds = document.getElementById('btn-clear-credentials');
  if (btnSaveClose && summaryCard && editWrapper) {
    btnSaveClose.onclick = async () => {
      // Speichere beide Bereiche in einem Schritt
      await applyProviderSettings();
      // Zugangsdaten (Bucket/Keys) zusammen mit Provider-Einstellungen übernehmen
      try {
        const body = {
          s3_bucket: document.getElementById('bucket-input')?.value || '',
          access_key_id: document.getElementById('ak-input')?.value || '',
          secret_access_key: document.getElementById('sk-input')?.value || ''
        };
        await call('api/set-overrides', { body: JSON.stringify(body) });
        out('Zugangsdaten gespeichert');
      } catch (e) {
        out('Fehler beim Speichern der Zugangsdaten: ' + e.message);
      }
      const btnApplyBackup = document.getElementById('btn-apply-backup');
      if (btnApplyBackup) btnApplyBackup.click();
      editWrapper.style.display = 'none';
      summaryCard.style.display = '';
      loadSummaryFromOverrides();
    };
  }
  if (btnClearCreds) {
    btnClearCreds.onclick = async () => {
      // Zugangsdaten leeren, um Providerwechsel zu ermöglichen
      try {
        const body = { s3_bucket: '', access_key_id: '', secret_access_key: '' };
        await call('api/set-overrides', { body: JSON.stringify(body) });
        const b = document.getElementById('bucket-input');
        const ak = document.getElementById('ak-input');
        const sk = document.getElementById('sk-input');
        if (b) b.value = '';
        if (ak) ak.value = '';
        if (sk) sk.value = '';
        out('Zugangsdaten gelöscht');
      } catch (e) {
        out('Fehler beim Löschen der Zugangsdaten: ' + e.message);
      }
    };
  }
  regionSelect.onchange = () => {
    if (regionSelect.value) { regionInput.value = regionSelect.value; out(`Region übernommen: ${regionSelect.value}`); regionDirty = true; }
  };
  regionInput.oninput = () => {
    const option = Array.from(regionSelect.options).find(opt => opt.value === regionInput.value);
    regionSelect.value = option ? regionInput.value : '';
    regionDirty = true;
  };
  endpointInput.addEventListener('input', () => { endpointDirty = true; });
  regionInput.removeAttribute('readonly');
  regionInput.removeAttribute('disabled');
  regionInput.style.pointerEvents = 'auto';
  regionInput.style.userSelect = 'text';
  regionInput.addEventListener('click', (e) => { e.stopPropagation(); e.preventDefault(); regionInput.focus(); regionInput.select(); });
  regionInput.addEventListener('dblclick', (e) => { e.stopPropagation(); regionInput.select(); });
  regionInput.addEventListener('focus', () => { if (!regionInput.value.trim()) regionInput.placeholder = 'z.B. eu-central-1, us-east-1, ap-southeast-1'; });
  regionInput.addEventListener('blur', () => { regionInput.placeholder = 'eu-central-1'; });

  // Gespeicherte Overrides laden und Felder befüllen
  async function loadOverridesAndPopulate() {
    try {
      const res = await call('api/get-overrides');
      if (!res.ok) return;
      const o = JSON.parse(res.body || '{}');

      // Provider aus Endpoint ableiten (best effort)
      const allCards = Array.from(document.querySelectorAll('.provider-card'));
      const matchCard = allCards.find(c => (c.dataset.ep || '').toLowerCase() === (o.s3_endpoint_url || '').toLowerCase());
      if (matchCard) {
        allCards.forEach(c => c.classList.remove('active'));
        matchCard.classList.add('active');
        selectedPreset = { ep: matchCard.dataset.ep, rg: matchCard.dataset.rg, fps: matchCard.dataset.fps, id: matchCard.dataset.provider };
        applyCapabilityUI(selectedPreset.id);
      }

      // Zugangsdaten
      const bucketEl = document.getElementById('bucket-input');
      const akEl = document.getElementById('ak-input');
      const skEl = document.getElementById('sk-input');
      if (bucketEl && o.s3_bucket) bucketEl.value = o.s3_bucket;
      if (akEl && o.access_key_id) akEl.value = o.access_key_id;
      // Secret nicht anzeigen – beim Speichern bleibt es durch Backend-Logik erhalten, wenn leer

      // Provider Felder
      if (endpointInput && o.s3_endpoint_url) { endpointInput.value = o.s3_endpoint_url; }
      if (prefixInput && typeof o.s3_prefix === 'string') { prefixInput.value = o.s3_prefix; }

      if (typeof o.force_path_style !== 'undefined') {
        const v = String(o.force_path_style).toLowerCase();
        document.getElementById('fps-input').checked = (v === 'true' || v === '1');
      }

      if (regionInput && (o.s3_region_name || o.s3_region_name === '')) {
        // Einige Provider brauchen keine Region – Feld ggf. leer lassen
        regionInput.value = o.s3_region_name || '';
        const opt = Array.from(regionSelect.options).find(opt => opt.value === regionInput.value);
        regionSelect.value = opt ? regionInput.value : '';
      }

      // Erweiterte Optionen
      const sseSel = document.getElementById('sse-select');
      const kmsEl = document.getElementById('kms-input');
      const verEl = document.getElementById('versioning-input');
      if (sseSel && typeof o.s3_sse !== 'undefined') sseSel.value = o.s3_sse || '';
      if (kmsEl && typeof o.s3_sse_kms_key_id !== 'undefined') kmsEl.value = o.s3_sse_kms_key_id || '';
      if (verEl && typeof o.enable_versioning !== 'undefined') verEl.checked = !!o.enable_versioning;

      // Backup Automatik / Retention
      const setIf = (id, val) => { const el = document.getElementById(id); if (!el) return; if (el.type === 'checkbox') el.checked = !!val; else if (typeof val !== 'undefined' && val !== null) el.value = val; };
      setIf('watch-ha-input', o.watch_ha_backups);
      setIf('upload-existing-input', o.upload_existing);
      setIf('delete-local-input', o.delete_local_after_upload);
      setIf('run-on-start-input', o.run_on_start);
      setIf('interval-input', o.backup_interval_hours);
      setIf('cron-input', o.backup_schedule_cron);
      setIf('keep-last-input', o.retention_keep_last_s3);
      setIf('retention-days-input', o.retention_days_s3);

      loadSummaryFromOverrides();
      out('Gespeicherte Einstellungen geladen');
    } catch (_) {}
  }

  // Initial laden
  loadOverridesAndPopulate();
}

async function applyProviderSettings() {
  const regionInput = document.getElementById('region-input');
  const regionSelect = document.getElementById('region-select');
  const endpointInput = document.getElementById('endpoint-input');
  const prefixInput = document.getElementById('prefix-input');
  const pathStyleCheckbox = document.getElementById('fps-input');
  const sseSelect = document.getElementById('sse-select');
  const kmsInput = document.getElementById('kms-input');
  const versioningCheckbox = document.getElementById('versioning-input');

  const providerId = (selectedPreset && selectedPreset.id) || document.querySelector('.provider-card.active')?.dataset.provider || 'aws';
  const caps = (typeof capsByProvider !== 'undefined' ? capsByProvider[providerId] : null) || {};

  const region = (regionInput.value && regionInput.value.trim()) || regionSelect.value || (selectedPreset && selectedPreset.rg) || '';
  const endpoint = endpointInput.value || (selectedPreset && selectedPreset.ep) || '';
  const pathStyle = pathStyleCheckbox.checked || (selectedPreset && selectedPreset.fps === 'true') || false;
  const sse = sseSelect ? sseSelect.value : '';
  const kms = kmsInput ? kmsInput.value.trim() : '';
  const enableVersioning = !!(versioningCheckbox && versioningCheckbox.checked);
  out('Wende Provider-Einstellungen an...');
  setLoading(true);
  try {
    const body = {
      s3_endpoint_url: endpoint,
      force_path_style: pathStyle,
      s3_prefix: prefixInput ? prefixInput.value : ''
    };
    // Nur senden, was der Provider unterstützt
    if (caps.region && region) body.s3_region_name = region;
    if (Array.isArray(caps.sse) && caps.sse.length > 0) body.s3_sse = sse || '';
    if (caps.kms) body.s3_sse_kms_key_id = kms || '';
    if (caps.versioning) body.enable_versioning = enableVersioning;
    const result = await call('api/set-overrides', { body: JSON.stringify(body) });
    out(result.body || (result.ok ? 'Provider-Einstellungen erfolgreich gespeichert!' : 'Fehler beim Speichern'));
  } catch (error) {
    out(`Fehler: ${error.message}`);
  } finally {
    setLoading(false);
  }
}


