// Mount a Vue app into a shadow root so Discourse's global CSS cannot bleed
// into our widget (and ours cannot bleed out). Returns the inner mount point
// the Vue app should target.
export function mountIntoShadow(host: HTMLElement): { mountPoint: HTMLElement } {
  const shadow = host.attachShadow({ mode: "open" });

  const style = document.createElement("style");
  style.textContent = `
    :host, .root { all: initial; font-family: -apple-system, system-ui, sans-serif; }
    .modal {
      position: fixed; inset: 0; display: none;
      align-items: center; justify-content: center;
      background: rgba(0,0,0,0.5); z-index: 2147483000;
    }
    .modal.open { display: flex; }
    .card {
      background: #fff; color: #111; border-radius: 12px;
      padding: 24px; max-width: 420px; width: 90%;
      box-shadow: 0 20px 60px rgba(0,0,0,0.3);
    }
    .card h2 { margin: 0 0 8px; font-size: 18px; }
    .card p  { margin: 0 0 16px; font-size: 14px; color: #555; }
    .actions { display: flex; gap: 8px; justify-content: flex-end; }
    .btn {
      border: 0; border-radius: 8px; padding: 8px 14px;
      font-size: 14px; cursor: pointer;
    }
    .btn.primary { background: #8e30eb; color: #fff; }
    .btn.ghost   { background: transparent; color: #555; }
    .err { color: #b00020; font-size: 13px; margin-top: 8px; }
  `;
  shadow.appendChild(style);

  const root = document.createElement("div");
  root.className = "root";
  shadow.appendChild(root);

  return { mountPoint: root };
}
