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
  // Beim Initialisieren Standard-Provider anwenden, falls aktiv markiert
  const active = document.querySelector('.provider-card.active');
  if (active) {
    selectedPreset = { ep: active.dataset.ep, rg: active.dataset.rg, fps: active.dataset.fps, id: active.dataset.provider };
    applyCapabilityUI(selectedPreset.id);
  }

  // Summary anzeigen
  function loadSummaryFromOverrides() {
    fetch('api/debug-log'); // noop to keep same origin warmed (no auth needed)
    // Wir lesen direkt die UI-Felder (Overlays spiegeln in run.sh wider). Optional: eigener endpoint
    const bucket = document.getElementById('bucket-input')?.value || '—';
    const prefix = '—';
    const endpoint = document.getElementById('endpoint-input')?.value || '—';
    const region = document.getElementById('region-input')?.value || '—';
    const sse = document.getElementById('sse-select')?.value || '—';
    const versioning = document.getElementById('versioning-input')?.checked ? 'aktiv' : 'aus';
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
  if (btnEdit && btnCancel && summaryCard && editWrapper) {
    btnEdit.onclick = () => { editWrapper.style.display = ''; summaryCard.style.display = 'none'; };
    btnCancel.onclick = () => { editWrapper.style.display = 'none'; summaryCard.style.display = ''; loadSummaryFromOverrides(); };
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
}

async function applyProviderSettings() {
  const regionInput = document.getElementById('region-input');
  const regionSelect = document.getElementById('region-select');
  const endpointInput = document.getElementById('endpoint-input');
  const pathStyleCheckbox = document.getElementById('fps-input');
  const sseSelect = document.getElementById('sse-select');
  const kmsInput = document.getElementById('kms-input');
  const versioningCheckbox = document.getElementById('versioning-input');

  const region = (regionInput.value && regionInput.value.trim()) || regionSelect.value || (selectedPreset && selectedPreset.rg) || 'us-east-1';
  const endpoint = endpointInput.value || (selectedPreset && selectedPreset.ep) || '';
  const pathStyle = pathStyleCheckbox.checked || (selectedPreset && selectedPreset.fps === 'true') || false;
  const sse = sseSelect ? sseSelect.value : '';
  const kms = kmsInput ? kmsInput.value.trim() : '';
  const enableVersioning = !!(versioningCheckbox && versioningCheckbox.checked);
  if (!region) { out('Fehler: Region ist erforderlich'); return; }
  out('Wende Provider-Einstellungen an...');
  setLoading(true);
  try {
    const result = await call('api/set-overrides', { body: JSON.stringify({
      s3_endpoint_url: endpoint,
      s3_region_name: region,
      force_path_style: pathStyle,
      s3_sse: sse,
      s3_sse_kms_key_id: kms,
      enable_versioning: enableVersioning
    })});
    out(result.body || (result.ok ? 'Provider-Einstellungen erfolgreich gespeichert!' : 'Fehler beim Speichern'));
  } catch (error) {
    out(`Fehler: ${error.message}`);
  } finally {
    setLoading(false);
  }
}


