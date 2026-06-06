/* ADC Risk Horizon — main.js */

// ── Mobile Nav ──────────────────────────────
const hamburger = document.getElementById('hamburger');
const mobileMenu = document.getElementById('mobileMenu');

hamburger.addEventListener('click', () => {
  mobileMenu.classList.toggle('open');
});

// Close mobile menu on link click
mobileMenu.querySelectorAll('a').forEach(link => {
  link.addEventListener('click', () => mobileMenu.classList.remove('open'));
});

// ── Scroll-based nav shadow ─────────────────
window.addEventListener('scroll', () => {
  const nav = document.getElementById('nav');
  nav.style.boxShadow = window.scrollY > 40
    ? '0 4px 24px rgba(0,0,0,0.25)'
    : 'none';
});

// ── Portfolio Loss Distribution Chart ───────
function drawLossChart(canvasId, width, height) {
  const canvas = document.getElementById(canvasId);
  if (!canvas) return;
  const ctx = canvas.getContext('2d');

  canvas.width  = width  || canvas.offsetWidth || 400;
  canvas.height = height || 200;

  const W = canvas.width;
  const H = canvas.height;

  // Generate normal-ish distribution data (20k paths simulation)
  const mean  = 0.045;
  const sigma = 0.008;
  const bins  = 60;
  const minX  = 0.02;
  const maxX  = 0.085;
  const step  = (maxX - minX) / bins;

  // Gaussian PDF
  function gauss(x) {
    return Math.exp(-0.5 * Math.pow((x - mean) / sigma, 2)) / (sigma * Math.sqrt(2 * Math.PI));
  }

  const data = [];
  let maxVal = 0;
  for (let i = 0; i < bins; i++) {
    const x = minX + i * step + step / 2;
    const y = gauss(x) * step * 20000; // scale to count
    data.push({ x, y });
    if (y > maxVal) maxVal = y;
  }

  // Layout
  const pad = { top: 20, right: 20, bottom: 36, left: 52 };
  const plotW = W - pad.left - pad.right;
  const plotH = H - pad.top  - pad.bottom;

  ctx.clearRect(0, 0, W, H);

  // Background
  ctx.fillStyle = '#f5f7fa';
  ctx.fillRect(0, 0, W, H);

  // Grid lines
  ctx.strokeStyle = '#dce4ed';
  ctx.lineWidth = 1;
  const yTicks = [0, 200, 400, 600, 800, 1000, 1200];
  yTicks.forEach(tick => {
    const y = pad.top + plotH - (tick / maxVal) * plotH;
    ctx.beginPath();
    ctx.moveTo(pad.left, y);
    ctx.lineTo(pad.left + plotW, y);
    ctx.stroke();
    ctx.fillStyle = '#8fa5bb';
    ctx.font = '10px DM Sans, sans-serif';
    ctx.textAlign = 'right';
    ctx.fillText(tick, pad.left - 6, y + 4);
  });

  // Bars
  const barW = plotW / bins;
  data.forEach((d, i) => {
    const bx = pad.left + i * barW;
    const bh = (d.y / maxVal) * plotH;
    const by = pad.top + plotH - bh;

    ctx.fillStyle = '#1a3a5c';
    ctx.globalAlpha = 0.85;
    ctx.fillRect(bx + 1, by, barW - 2, bh);
  });
  ctx.globalAlpha = 1;

  // VaR lines
  const var99_5 = 0.063;
  const var99_9 = 0.068;

  function xToCanvas(xVal) {
    return pad.left + ((xVal - minX) / (maxX - minX)) * plotW;
  }

  // VaR 99.5%
  ctx.strokeStyle = '#f4a829';
  ctx.lineWidth = 2;
  ctx.setLineDash([5, 4]);
  ctx.beginPath();
  ctx.moveTo(xToCanvas(var99_5), pad.top);
  ctx.lineTo(xToCanvas(var99_5), pad.top + plotH);
  ctx.stroke();

  // VaR 99.9%
  ctx.strokeStyle = '#e05c3a';
  ctx.beginPath();
  ctx.moveTo(xToCanvas(var99_9), pad.top);
  ctx.lineTo(xToCanvas(var99_9), pad.top + plotH);
  ctx.stroke();
  ctx.setLineDash([]);

  // X-axis labels
  ctx.fillStyle = '#8fa5bb';
  ctx.font = '10px DM Sans, sans-serif';
  ctx.textAlign = 'center';
  [0.02, 0.03, 0.04, 0.05, 0.06, 0.07, 0.08].forEach(val => {
    const x = xToCanvas(val);
    ctx.fillText(val.toFixed(2), x, pad.top + plotH + 16);
  });

  // X-axis label
  ctx.fillStyle = '#5b7a99';
  ctx.font = '11px DM Sans, sans-serif';
  ctx.textAlign = 'center';
  ctx.fillText('Loss (USD billions)', pad.left + plotW / 2, H - 4);

  // Legend
  const legendX = W - pad.right - 140;
  const legendY = pad.top + 8;
  ctx.font = '10px DM Sans, sans-serif';
  ctx.textAlign = 'left';

  ctx.strokeStyle = '#e05c3a';
  ctx.lineWidth = 2;
  ctx.setLineDash([5, 4]);
  ctx.beginPath();
  ctx.moveTo(legendX, legendY + 5);
  ctx.lineTo(legendX + 18, legendY + 5);
  ctx.stroke();
  ctx.setLineDash([]);
  ctx.fillStyle = '#5b7a99';
  ctx.fillText('VaR99.9%=0.07B', legendX + 22, legendY + 9);

  ctx.strokeStyle = '#f4a829';
  ctx.lineWidth = 2;
  ctx.setLineDash([5, 4]);
  ctx.beginPath();
  ctx.moveTo(legendX, legendY + 20);
  ctx.lineTo(legendX + 18, legendY + 20);
  ctx.stroke();
  ctx.setLineDash([]);
  ctx.fillStyle = '#5b7a99';
  ctx.fillText('VaR99.5%=0.06B', legendX + 22, legendY + 24);
}

// Draw charts after fonts load
document.fonts.ready.then(() => {
  drawLossChart('lossChart',    400, 200);
  drawLossChart('contactChart', 420, 260);
});

// ── Scroll reveal ────────────────────────────
const observer = new IntersectionObserver((entries) => {
  entries.forEach(entry => {
    if (entry.isIntersecting) {
      entry.target.style.opacity    = '1';
      entry.target.style.transform  = 'translateY(0)';
    }
  });
}, { threshold: 0.1 });

document.querySelectorAll('.service-card, .appt-card, .blog-card').forEach(el => {
  el.style.opacity   = '0';
  el.style.transform = 'translateY(24px)';
  el.style.transition = 'opacity 0.5s ease, transform 0.5s ease';
  observer.observe(el);
});

// ── Subscribe form placeholder ───────────────
document.getElementById('subscribeForm')?.addEventListener('submit', (e) => {
  e.preventDefault();
  // TODO: Replace with Mailchimp form action URL
  alert('Thank you for subscribing! We\'ll be in touch.');
  e.target.reset();
});
