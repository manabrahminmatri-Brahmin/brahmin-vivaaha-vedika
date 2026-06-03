"""Patch web_deploy/index.html to match app content."""
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
p = ROOT / "web_deploy" / "index.html"
text = p.read_text(encoding="utf-8")

def replace_between(text: str, start_marker: str, end_marker: str, new: str) -> str:
    start = text.index(start_marker)
    end = text.index(end_marker)
    return text[:start] + new + text[end:]

NEW_INTRO = """  <!-- ── About (matches app About screen) ── -->
  <section class="section" style="padding-top:56px;" id="about">
    <div class="wrap">
      <div class="section-head reveal">
        <span class="eyebrow">Our Mission</span>
        <h2>Built for Telugu Brahmin families</h2>
        <p class="plans-intro" style="margin-bottom:0;">mana Vivaaha Vedika is dedicated to helping Brahmin families find suitable matches while preserving our cultural values and traditions. We understand the importance of compatibility, family values, and cultural alignment in marriage alliances.</p>
      </div>
    </div>
  </section>

  <!-- ── Key Features (app About → Key Features) ── -->
  <section class="section alt" id="features">
    <div class="wrap">
      <div class="section-head reveal">
        <span class="eyebrow">Key Features</span>
        <h2>What you get in the app</h2>
        <p>Same features listed in Settings → About in mana Vivaaha Vedika.</p>
      </div>
      <div class="why-grid">
        <article class="why-card reveal"><div class="icon">☸</div><h3>Ashtakoot compatibility</h3><p>Vedic 8-parameter matching on profiles with birth details — scores out of 36 points.</p></article>
        <article class="why-card reveal"><div class="icon">🔐</div><h3>Secure MPIN login</h3><p>OTP-verified registration, then your private MPIN (and optional biometric) to open the app.</p></article>
        <article class="why-card reveal"><div class="icon">👨‍👩‍👧</div><h3>Family-managed profiles</h3><p>Parents and guardians can help manage the profile and matrimony search, as families prefer.</p></article>
        <article class="why-card reveal"><div class="icon">🛡</div><h3>Privacy controls</h3><p>Mask photos, identity, contacts, and chat previews until you allow — consistent across lists and chat.</p></article>
        <article class="why-card reveal"><div class="icon">💬</div><h3>Direct communication</h3><p>Send interest, photo requests, and chat with accepted matches; manage Received and Sent in the Interests hub.</p></article>
        <article class="why-card reveal"><div class="icon">📱</div><h3>Mobile OTP verification</h3><p>Every account is tied to a verified Indian mobile number at registration.</p></article>
      </div>
    </div>
  </section>

  <!-- ── Our Values (app About → Our Values) ── -->
  <section class="section" id="values">
    <div class="wrap">
      <div class="section-head reveal">
        <span class="eyebrow">Our Values</span>
        <h2>How we serve the community</h2>
      </div>
      <div class="why-grid">
        <article class="why-card reveal"><div class="icon">🪷</div><h3>Cultural preservation</h3><p>Respect for Brahmin traditions, gotra, and family-led alliances.</p></article>
        <article class="why-card reveal"><div class="icon">🏠</div><h3>Family-centric approach</h3><p>Designed for parents, guardians, and candidates working together.</p></article>
        <article class="why-card reveal"><div class="icon">🔒</div><h3>Privacy &amp; security</h3><p>MPIN, OTP, and profile privacy settings you control.</p></article>
        <article class="why-card reveal"><div class="icon">✓</div><h3>Authentic profiles</h3><p>Complete verification steps in Profile to improve trust and visibility.</p></article>
        <article class="why-card reveal"><div class="icon">⚡</div><h3>Tradition + convenience</h3><p>Classic matrimony values with a modern Android app experience.</p></article>
      </div>
    </div>
  </section>

  <!-- ── App capabilities (real screens & flows) ── -->
  <section class="section alt" id="app-flows">
    <div class="wrap">
      <div class="section-head reveal">
        <span class="eyebrow">Inside the app</span>
        <h2>Search, match, and connect</h2>
        <p>Use Search &amp; Filters, partner preferences in your profile wizard, and Platinum tools when you upgrade.</p>
      </div>
      <div class="why-grid">
        <article class="why-card reveal"><div class="icon">🔍</div><h3>Search &amp; filters</h3><p>Filter by gotra, age, location, education, and more from the in-app search screen.</p></article>
        <article class="why-card reveal"><div class="icon">💌</div><h3>Interests</h3><p>Send Interest from a profile; track Received and Sent tabs, including withdraw and reminder on pending sent items.</p></article>
        <article class="why-card reveal"><div class="icon">📸</div><h3>Photo requests</h3><p>Request private photos — accept or decline in Received; withdraw or remind from Sent.</p></article>
        <article class="why-card reveal"><div class="icon">📨</div><h3>Messages</h3><p>Chat with accepted matches only; unread badge counts chat messages (not photo requests or wishes).</p></article>
        <article class="why-card reveal"><div class="icon">🎠</div><h3>Discover 3D</h3><p>Platinum members open Discover 3D from the Home tab (floating control) for compatible profiles.</p></article>
        <article class="why-card reveal"><div class="icon">👥</div><h3>Community Heads</h3><p>Platinum access to Community Heads details and community reference requests.</p></article>
      </div>
      <p class="plans-footnote reveal" style="margin-top:28px;">Partner preferences (age, gotra, education, location, etc.) are set in Profile → Edit Profile in the app — not on this website.</p>
    </div>
  </section>

"""

text = replace_between(
    text,
    "  <!-- ── Quick Search Bar ── -->",
    "  <!-- ── How It Works ── -->",
    NEW_INTRO,
)

# Update How It Works steps
text = text.replace(
    """        <p>Your journey to a perfect alliance in just four easy steps.</p>
      </div>
      <div class="how-steps">
        <div class="step-card reveal">
          <div class="step-num">1</div>
          <h3>Download & Register</h3>
          <p>Install the app, verify your mobile via OTP, and set up your secure MPIN in minutes.</p>
        </div>
        <div class="step-card reveal">
          <div class="step-num">2</div>
          <h3>Create Your Profile</h3>
          <p>Add horoscope, gotram, education, and family details. Upload photos with privacy controls.</p>
        </div>
        <div class="step-card reveal">
          <div class="step-num">3</div>
          <h3>Browse & Match</h3>
          <p>Discover profiles. Our Ashtakoot engine shows compatibility scores instantly.</p>
        </div>
        <div class="step-card reveal">
          <div class="step-num">4</div>
          <h3>Connect & Celebrate</h3>
          <p>Express interest, get approval, and connect via WhatsApp — then celebrate your alliance!</p>
        </div>
      </div>""",
    """        <p>The same flow as the mana Vivaaha Vedika Android app.</p>
      </div>
      <div class="how-steps">
        <div class="step-card reveal">
          <div class="step-num">1</div>
          <h3>Download &amp; register</h3>
          <p>Install from Google Play, verify your mobile with OTP, and set your secure MPIN.</p>
        </div>
        <div class="step-card reveal">
          <div class="step-num">2</div>
          <h3>Complete your profile</h3>
          <p>Add birth details, gotra, family, education, photos, and partner preferences in the profile wizard.</p>
        </div>
        <div class="step-card reveal">
          <div class="step-num">3</div>
          <h3>Browse &amp; match</h3>
          <p>Search and filter profiles; view Ashtakoot scores; send interest and photo requests.</p>
        </div>
        <div class="step-card reveal">
          <div class="step-num">4</div>
          <h3>Upgrade to Platinum</h3>
          <p>Unlock photos, contacts, WhatsApp messaging, Discover 3D, and more — pay via Razorpay (UPI/card) in the app.</p>
        </div>
        <div class="step-card reveal">
          <div class="step-num">5</div>
          <h3>Connect with families</h3>
          <p>Chat with accepted matches; use WhatsApp when interest is mutual; get help via in-app support or WhatsApp.</p>
        </div>
      </div>""",
)

# Remove Why Choose Us duplicate section (features already covered)
text = replace_between(
    text,
    "  <!-- ── Why Choose Us ── -->",
    "  <!-- ── Partner Preferences ── -->",
    "",
)

# Remove Partner Preferences web form
text = replace_between(
    text,
    "  <!-- ── Partner Preferences ── -->",
    "  <!-- ── Register ── -->",
    "",
)

# Update register perks
text = text.replace(
    """          <ul class="perks">
            <li>Free profile creation</li>
            <li>Ashtakoot compatibility report</li>
            <li>Privacy controls for photos</li>
            <li>Family can manage your profile</li>
          </ul>""",
    """          <ul class="perks">
            <li>Free registration (₹0)</li>
            <li>View profiles &amp; About Me (photos blurred until Platinum)</li>
            <li>Ashtakoot on profiles with birth details</li>
            <li>Family-managed profile &amp; privacy controls</li>
          </ul>""",
)
text = text.replace(
    """          <ul class="perks">
            <li>Free profile creation</li>
            <li>Unlimited profile browsing</li>
            <li>Express interest in matches</li>
            <li>Secure MPIN login</li>
          </ul>""",
    """          <ul class="perks">
            <li>Free registration (₹0)</li>
            <li>Search, filter &amp; send interest</li>
            <li>Receive interest requests</li>
            <li>OTP + secure MPIN login</li>
          </ul>""",
)

# Plans payment note
text = text.replace(
    "Pay securely via UPI in the app.",
    "Pay in the app via Razorpay (UPI, card, netbanking). Prices shown exclude 18% GST added at checkout, same as the Premium screen.",
)

# Remove platinum highlights, fake gotra counts, stories, blog
text = replace_between(
    text,
    "  <!-- ── Platinum Highlights ── -->",
    "  <!-- ── App Download CTA ── -->",
    "",
)

# Update download CTA
text = text.replace(
    "Join thousands of Brahmin families finding their perfect alliance. Free to download, free to register. Available on Android — iOS coming soon.",
    "Free to download and register on Android. Upgrade to Platinum inside the app when you are ready to connect.",
)

# FAQ block - replace entire faq-list inner content
OLD_FAQ_START = '      <div class="faq-list reveal">'
OLD_FAQ_END = '      </div>\n    </div>\n  </section>\n\n  <!-- ── Contact / Support ── -->'
faq_start = text.index(OLD_FAQ_START)
faq_end = text.index(OLD_FAQ_END)
NEW_FAQ = """      <div class="faq-list reveal">
        <div class="faq-item">
          <div class="faq-question" onclick="toggleFaq(this)">What makes mana Vivaaha Vedika special?<span class="faq-icon">+</span></div>
          <div class="faq-answer">We combine traditional Vedic compatibility with modern discovery and privacy-first controls. You get curated interests, structured requests, profile analytics, and real-time updates in one place.</div>
        </div>
        <div class="faq-item">
          <div class="faq-question" onclick="toggleFaq(this)">Is registration free?<span class="faq-icon">+</span></div>
          <div class="faq-answer">Yes. Registration is ₹0. You can view profile details, read About Me, use basic sorting and filtering, edit your profile, and receive interest requests. Profile photos stay blurred until you upgrade to Platinum (₹99 / 1 month, ₹297 / 3 months, ₹594 / 6 months, ₹1,188 / 12 months).</div>
        </div>
        <div class="faq-item">
          <div class="faq-question" onclick="toggleFaq(this)">Where is Discover 3D?<span class="faq-icon">+</span></div>
          <div class="faq-answer">Discover 3D is a Platinum feature. Platinum members can open it from the Home tab using the floating Discover 3D control.</div>
        </div>
        <div class="faq-item">
          <div class="faq-question" onclick="toggleFaq(this)">How do Interests work?<span class="faq-icon">+</span></div>
          <div class="faq-answer">Use Send Interest from a profile. Received interests are in the Received tab; sent interests are in the Sent tab with status tracking. Withdraw and Reminder for pending sent items are managed in the Sent tab only.</div>
        </div>
        <div class="faq-item">
          <div class="faq-question" onclick="toggleFaq(this)">How do Photo Requests work?<span class="faq-icon">+</span></div>
          <div class="faq-answer">Photo requests appear in Received and Sent. In Received, accept or decline. In Sent, withdraw or send a reminder for pending requests.</div>
        </div>
        <div class="faq-item">
          <div class="faq-question" onclick="toggleFaq(this)">What appears in the Messages tab?<span class="faq-icon">+</span></div>
          <div class="faq-answer">Messages lists chat conversations with accepted matches only. The badge counts unread chat messages. Photo requests and birthday wishes stay in Received or Notifications — not Messages.</div>
        </div>
        <div class="faq-item">
          <div class="faq-question" onclick="toggleFaq(this)">What is included in Platinum?<span class="faq-icon">+</span></div>
          <div class="faq-answer">All Platinum durations include: unlimited contact requests, direct WhatsApp messaging, advanced compatibility matching, priority profile visibility, view contact information, access Community Heads details, community reference requests, send interest, profile highlighter, read receipts, advanced filters, and incognito mode.</div>
        </div>
        <div class="faq-item">
          <div class="faq-question" onclick="toggleFaq(this)">How do I contact support?<span class="faq-icon">+</span></div>
          <div class="faq-answer">In the app: Settings → Support → Chat with Support, or use Call / WhatsApp / Email on Help &amp; Support. WhatsApp: +91 8985936678 · Email: support@manaVivaahaVedika.in. Share your profile ID and a screenshot for faster help.</div>
        </div>
      </div>
    </div>
  </section>

  <!-- ── Contact / Support ── -->"""
text = text[:faq_start] + NEW_FAQ + text[faq_end + len(OLD_FAQ_END):]

# Contact section
text = text.replace(
    """        <p>Reach out any time — our team is available 24×7 to assist your family.</p>
      </div>
      <div class="contact-grid">
        <div class="contact-card reveal">
          <div class="contact-icon">💬</div>
          <h4>WhatsApp Support</h4>
          <p>Chat with us instantly — fastest way to get help, day or night.</p>
          <a href="https://wa.me/918985936678" target="_blank" rel="noopener">+91 8985936678</a>
        </div>
        <div class="contact-card reveal">
          <div class="contact-icon">📧</div>
          <h4>Email Support</h4>
          <p>Send us your queries, profile help requests, or feedback anytime.</p>
          <a href="mailto:support@manaVivaahaVedika.in">support@manaVivaahaVedika.in</a>
        </div>
        <div class="contact-card reveal">
          <div class="contact-icon">📞</div>
          <h4>Phone Support</h4>
          <p>Speak directly with our matrimony advisors for personalised help.</p>
          <a href="tel:+918985936678">+91 8985936678</a>
        </div>
      </div>""",
    """        <p>Same options as Settings → Help &amp; Support in the app.</p>
      </div>
      <div class="contact-grid">
        <div class="contact-card reveal">
          <div class="contact-icon">💬</div>
          <h4>In-app chat</h4>
          <p>Settings → Support → Chat with Support (fastest inside the app).</p>
          <a href="https://play.google.com/store/apps/details?id=com.manavivaahavedika.brahmin" target="_blank" rel="noopener">Open app</a>
        </div>
        <div class="contact-card reveal">
          <div class="contact-icon">📱</div>
          <h4>WhatsApp</h4>
          <p>Direct WhatsApp support (same number as in the app).</p>
          <a href="https://wa.me/918985936678" target="_blank" rel="noopener">+91 8985936678</a>
        </div>
        <div class="contact-card reveal">
          <div class="contact-icon">📧</div>
          <h4>Email</h4>
          <p>support@manaVivaahaVedika.in</p>
          <a href="mailto:support@manaVivaahaVedika.in">support@manaVivaahaVedika.in</a>
        </div>
        <div class="contact-card reveal">
          <div class="contact-icon">📞</div>
          <h4>Phone</h4>
          <p>Call support from Help &amp; Support in the app.</p>
          <a href="tel:+918985936678">+91 8985936678</a>
        </div>
      </div>""",
)

# Footer
text = text.replace(
    """        <ul>
          <li><a href="#profiles">Browse Profiles</a></li>
          <li><a href="#register">Register Free</a></li>
          <li><a href="#plans">Membership Plans</a></li>
          <li><a href="#platinum">Platinum Benefits</a></li>
          <li><a href="#how">How It Works</a></li>
        </ul>""",
    """        <ul>
          <li><a href="#features">Features</a></li>
          <li><a href="#register">Register Free</a></li>
          <li><a href="#plans">Membership Plans</a></li>
          <li><a href="#how">How It Works</a></li>
          <li><a href="privacy.html">Privacy Policy</a></li>
        </ul>""",
)
text = text.replace(
    """        <h4>Community</h4>
        <ul>
          <li><a href="#community">Browse by Gotra</a></li>
          <li><a href="#stories">Success Stories</a></li>
          <li><a href="#blog">Matrimony Tips</a></li>
          <li><a href="#faq">FAQ</a></li>
          <li><a href="#screenshots">App Preview</a></li>
        </ul>""",
    """        <h4>Legal</h4>
        <ul>
          <li><a href="privacy.html">Privacy Policy</a></li>
          <li><a href="#faq">FAQ</a></li>
          <li><a href="#contact">Contact</a></li>
        </ul>""",
)
text = text.replace(
    "మన వివాహ వేదిక — Connecting Brahmin hearts with tradition, trust, and technology across Telugu states.",
    "మన వివాహ వేదిక — Where Tradition Meets Technology",
)
text = text.replace("&copy; 2026 mana Vivaaha Vedika", "&copy; 2025 mana Vivaaha Vedika")
text = text.replace("&copy; 2026 మన వివాహ వేదిక", "&copy; 2025 మన వివాహ వేదిక")

# Script cleanup
text = text.replace(
    """      // Animated counters
      function animateCounter(el) {
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

      // Scroll reveal + counters
      var io = new IntersectionObserver(function (entries) {
        entries.forEach(function (e) {
          if (e.isIntersecting) {
            e.target.classList.add('visible');
            e.target.querySelectorAll && e.target.querySelectorAll('.num[data-target]').forEach(function (n) {
              if (!n.dataset.done) { n.dataset.done = '1'; animateCounter(n); }
            });
          }
        });
      }, { threshold: 0.12 });

      document.querySelectorAll('.reveal').forEach(function (el) { io.observe(el); });
      var statsEl = document.getElementById('stats');
      if (statsEl) io.observe(statsEl);

      // Carousel
      var carousel = document.getElementById('carousel');
      var prev = document.getElementById('carouselPrev');
      var next = document.getElementById('carouselNext');
      if (carousel && prev && next) {
        var scrollAmt = 284;
        prev.addEventListener('click', function () { carousel.scrollBy({ left: -scrollAmt, behavior: 'smooth' }); });
        next.addEventListener('click', function () { carousel.scrollBy({ left: scrollAmt, behavior: 'smooth' }); });
      }

      // Profile tab filter
      window.filterProfiles = function (type, btn) {
        document.querySelectorAll('.tab-btn').forEach(function (b) { b.classList.remove('active'); });
        btn.classList.add('active');
        document.querySelectorAll('.profile-card').forEach(function (card) {
          if (type === 'all') {
            card.style.display = '';
          } else {
            var types = card.dataset.type || '';
            card.style.display = types.includes(type) ? '' : 'none';
          }
        });
      };

      // FAQ accordion""",
    """      // Scroll reveal
      var io = new IntersectionObserver(function (entries) {
        entries.forEach(function (e) {
          if (e.isIntersecting) e.target.classList.add('visible');
        });
      }, { threshold: 0.12 });
      document.querySelectorAll('.reveal').forEach(function (el) { io.observe(el); });

      // FAQ accordion""",
)

# contact grid 4 columns on desktop - add quick css
if ".contact-grid { display: grid; grid-template-columns: repeat(3, 1fr)" in text:
    text = text.replace(
        ".contact-grid { display: grid; grid-template-columns: repeat(3, 1fr); gap: 24px; }",
        ".contact-grid { display: grid; grid-template-columns: repeat(4, 1fr); gap: 24px; }",
    )
    text = text.replace(
        "      .contact-grid { grid-template-columns: 1fr; }",
        "      .contact-grid { grid-template-columns: 1fr 1fr; }\n      @media (max-width: 600px) { .contact-grid { grid-template-columns: 1fr; } }",
    )

p.write_text(text, encoding="utf-8")
print("Patched", p)
