import re
import subprocess
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
html = subprocess.check_output(
    ["git", "show", "14e81fa^:web_deploy/index.html"],
    cwd=ROOT,
)
text = html.decode("utf-8")

profiles_block = text[
    text.index("  <!-- ── Quick Search Bar ── -->") : text.index(
        "  <!-- ── How It Works ── -->"
    )
]
community_block = text[
    text.index("  <!-- ── Gotras / Community ── -->") : text.index(
        "  <!-- ── Testimonials ── -->"
    )
]
community_block = re.sub(
    r'<div class="gotra-count">[^<]+</div>',
    '<div class="gotra-count">Filter in app</div>',
    community_block,
)
profiles_block = profiles_block.replace(
    "Verified Brahmin profiles across Andhra Pradesh and Telangana — updated daily.",
    "Sample profiles for preview — open the app to browse and match real members.",
)

cur_path = ROOT / "web_deploy" / "index.html"
cur = cur_path.read_text(encoding="utf-8")

marker_about = "  <!-- ── About (matches app About screen) ── -->"
if 'id="profiles"' not in cur:
    cur = cur.replace(marker_about, profiles_block + marker_about)

marker_how = "  <!-- ── How It Works ── -->"
if 'id="community"' not in cur:
    cur = cur.replace(marker_how, community_block + marker_how)

if '<li><a href="#profiles">Profiles</a></li>' not in cur:
    cur = cur.replace(
        '<li><a href="#features">Features</a></li>',
        '<li><a href="#profiles">Profiles</a></li>\n        <li><a href="#features">Features</a></li>',
    )

if "Browse Profiles" not in cur:
    cur = cur.replace(
        '<li><a href="#features">Features</a></li>\n          <li><a href="#register">Register Free</a></li>',
        '<li><a href="#profiles">Browse Profiles</a></li>\n          <li><a href="#features">Features</a></li>\n          <li><a href="#community">By Gotra</a></li>\n          <li><a href="#register">Register Free</a></li>',
    )

if "filterProfiles" not in cur:
    cur = cur.replace(
        """      // Scroll reveal
      var io = new IntersectionObserver(function (entries) {
        entries.forEach(function (e) {
          if (e.isIntersecting) e.target.classList.add('visible');
        });
      }, { threshold: 0.12 });
      document.querySelectorAll('.reveal').forEach(function (el) { io.observe(el); });

      // FAQ accordion""",
        """      function animateCounter(el) {
        var target = parseInt(el.dataset.target, 10);
        var suffix = el.dataset.suffix || '';
        var duration = 1800;
        var startTime = null;
        function step(ts) {
          if (!startTime) startTime = ts;
          var p = Math.min((ts - startTime) / duration, 1);
          var ease = 1 - Math.pow(1 - p, 3);
          el.textContent = Math.floor(ease * target).toLocaleString('en-IN') + suffix;
          if (p < 1) requestAnimationFrame(step);
        }
        requestAnimationFrame(step);
      }

      var io = new IntersectionObserver(function (entries) {
        entries.forEach(function (e) {
          if (e.isIntersecting) {
            e.target.classList.add('visible');
            if (e.target.querySelectorAll) {
              e.target.querySelectorAll('.num[data-target]').forEach(function (n) {
                if (!n.dataset.done) { n.dataset.done = '1'; animateCounter(n); }
              });
            }
          }
        });
      }, { threshold: 0.12 });
      document.querySelectorAll('.reveal').forEach(function (el) { io.observe(el); });
      var statsEl = document.getElementById('stats');
      if (statsEl) io.observe(statsEl);

      window.filterProfiles = function (type, btn) {
        document.querySelectorAll('.tab-btn').forEach(function (b) { b.classList.remove('active'); });
        btn.classList.add('active');
        document.querySelectorAll('.profile-card').forEach(function (card) {
          if (type === 'all') { card.style.display = ''; return; }
          var types = card.dataset.type || '';
          card.style.display = types.includes(type) ? '' : 'none';
        });
      };

      // FAQ accordion""",
    )

cur_path.write_text(cur, encoding="utf-8")
print("Restored profiles + community sections")
