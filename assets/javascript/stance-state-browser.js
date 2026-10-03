(() => {
  const root = document.getElementById('stance-state-browser');
  if (!root) return;

  // The complete table remains visible when Bootstrap is unavailable.
  if (window.bootstrap && window.bootstrap.Tab) {
    root.querySelector('[role="tablist"]').hidden = false;
    const views = { map: 'stance-map-tab', table: 'stance-states-tab' };
    Object.entries(views).forEach(([view, buttonId]) => {
      const panel = root.querySelector(`#${view}`);
      panel.classList.add('tab-pane');
      panel.classList.toggle('active', view === 'map');
      panel.setAttribute('role', 'tabpanel');
      panel.setAttribute('aria-labelledby', buttonId);
      panel.tabIndex = 0;
    });
    root.querySelectorAll('[data-bs-toggle="tab"]').forEach((button) => {
      bootstrap.Tab.getOrCreateInstance(button);

    });

  }

  const tableBody = root.querySelector('tbody');
  const rows = Array.from(tableBody.rows);
  const input = root.querySelector('#stance-state-query');
  const sortButtons = root.querySelectorAll('[data-state-sort]');
  let sortKey = 'name';
  let ascending = true;

  function render() {
    const query = input.value.trim().toLocaleLowerCase();
    let visible = 0;
    rows.sort((left, right) => {
      const alphabetical = left.dataset.stateName.localeCompare(right.dataset.stateName);
      if (sortKey === 'name') return ascending ? alphabetical : -alphabetical;
      const difference = Number(left.dataset[sortKey]) - Number(right.dataset[sortKey]);
      return (ascending ? difference : -difference) || alphabetical;
    });
    rows.forEach((row) => {
      row.hidden = !`${row.dataset.stateName} ${row.dataset.stateCode}`.toLocaleLowerCase().includes(query);
      if (!row.hidden) visible += 1;
      tableBody.append(row);
    });
    root.querySelector('[data-state-count]').textContent = `${visible} of ${rows.length} entries`;
    root.querySelector('[data-state-empty]').hidden = visible !== 0;
    sortButtons.forEach((button) => {
      const selected = button.dataset.stateSort === sortKey;
      button.closest('th').removeAttribute('aria-sort');
      if (selected) button.closest('th').setAttribute('aria-sort', ascending ? 'ascending' : 'descending');
      const icon = button.querySelector('[data-sort-indicator]');
      icon.classList.remove('fa-sort', 'fa-sort-up', 'fa-sort-down');
      icon.classList.add(selected ? (ascending ? 'fa-sort-up' : 'fa-sort-down') : 'fa-sort');
    });
  }

  root.querySelector('[data-state-search]').hidden = false;
  input.addEventListener('input', render);
  sortButtons.forEach((button) => {
    button.disabled = false;
    button.addEventListener('click', () => {
      const nextKey = button.dataset.stateSort;
      ascending = nextKey === sortKey ? !ascending : nextKey === 'name';
      sortKey = nextKey;
      render();
    });
  });
  render();
})();
