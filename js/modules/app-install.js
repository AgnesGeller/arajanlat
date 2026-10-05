// Installation preferences only; customer and quote data are never stored here.
const installedKey = 'quote_pwa_installed';
const standalone = window.matchMedia('(display-mode: standalone)');
const button = document.querySelector('#install-app');
let installPrompt = null;
let knownInstalled = false;
let feedbackTimer;
function showInstalledFeedback() {
  clearTimeout(feedbackTimer);
  document.querySelector('#install-feedback')?.remove();
  const feedback = document.createElement('div');
  feedback.id = 'install-feedback';
  feedback.className = 'install-feedback';
  feedback.setAttribute('role', 'status');
  feedback.setAttribute('aria-live', 'polite');
  document.body.append(feedback);
  feedback.textContent = 'Az app telepítése sikeres.';
  feedbackTimer = setTimeout(() => feedback.remove(), 2000);
}
function rememberInstalled(value) {
  knownInstalled = value;
  try { value ? localStorage.setItem(installedKey, 'yes') : localStorage.removeItem(installedKey); } catch { /* Storage can be unavailable in private browsing. */ }
}
function updateButton() {
  const runningInstalled = standalone.matches;
  if (runningInstalled) rememberInstalled(true);
  button.hidden = runningInstalled || knownInstalled || !installPrompt;
}
try { knownInstalled = localStorage.getItem(installedKey) === 'yes'; } catch { /* Use browser signals. */ }
window.addEventListener('beforeinstallprompt', event => {
  event.preventDefault();
  installPrompt = event;
  // A fresh install offer also handles an app that was subsequently removed.
  rememberInstalled(false);
  updateButton();
});
window.addEventListener('appinstalled', () => {
  installPrompt = null;
  rememberInstalled(true);
  updateButton();
  showInstalledFeedback();
});
standalone.addEventListener('change', updateButton);
button.addEventListener('click', async () => {
  if (!installPrompt) return;
  const prompt = installPrompt;
  installPrompt = null;
  button.disabled = true;
  try {
    await prompt.prompt();
    const choice = await prompt.userChoice;
    if (choice.outcome === 'accepted') rememberInstalled(true);
  } catch {
    document.querySelector('#status').textContent = 'A telepítés nem indult el. Nyisd meg az alkalmazást Chrome vagy Edge böngészőben, majd próbáld újra.';
  } finally { button.disabled = false; updateButton(); }
});
updateButton();
