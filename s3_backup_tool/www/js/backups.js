// renderBackups Funktion wurde entfernt, da das Backups-Tab entfernt wurde

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


