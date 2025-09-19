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
        <button class="btn btn-secondary btn-sm restore-btn" data-slug="${backup.slug}">Auswählen</button>
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


