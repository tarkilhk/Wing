const tabs = [...document.querySelectorAll('[role="tab"]')];
const panels = [...document.querySelectorAll('[role="tabpanel"]')];
const stage = document.querySelector('.work-stage');

function selectTab(tab, pointerInitiated = false) {
  stage.dataset.pointerChange = String(pointerInitiated);
  for (const candidate of tabs) {
    const selected = candidate === tab;
    candidate.setAttribute('aria-selected', String(selected));
    candidate.tabIndex = selected ? 0 : -1;
  }
  for (const panel of panels) {
    panel.hidden = panel.id !== tab.getAttribute('aria-controls');
  }
}

for (const tab of tabs) {
  tab.addEventListener('click', event => selectTab(tab, event.detail > 0));
  tab.addEventListener('keydown', event => {
    let index = tabs.indexOf(tab);
    if (event.key === 'ArrowRight' || event.key === 'ArrowDown') index++;
    else if (event.key === 'ArrowLeft' || event.key === 'ArrowUp') index--;
    else if (event.key === 'Home') index = 0;
    else if (event.key === 'End') index = tabs.length - 1;
    else return;
    event.preventDefault();
    const next = tabs[(index + tabs.length) % tabs.length];
    selectTab(next);
    next.focus();
  });
}

const appearanceButtons = [...document.querySelectorAll('[data-theme]')];
for (const button of appearanceButtons) {
  button.addEventListener('click', () => {
    const theme = button.dataset.theme;
    for (const candidate of appearanceButtons) {
      candidate.setAttribute('aria-pressed', String(candidate === button));
    }
    for (const image of document.querySelectorAll('[data-app-image]')) {
      const path = `assets/screenshots/${image.dataset.appImage}-${theme}.png`;
      image.src = path;
      image.closest('figure').querySelector('[data-expand-image]').href = path;
    }
  });
}
