function initializeProviders() {
  const providerCards = document.querySelectorAll('.provider-card');
  providerCards.forEach(card => {
    card.onclick = () => {
      providerCards.forEach(c => c.classList.remove('active'));
      card.classList.add('active');
      selectedPreset = { ep: card.dataset.ep, rg: card.dataset.rg, fps: card.dataset.fps };
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

  const regionInput = document.getElementById('region-input');
  const regionSelect = document.getElementById('region-select');
  const endpointInput = document.getElementById('endpoint-input');
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


