// Year
const yearEl = document.getElementById("year");
if (yearEl) yearEl.textContent = new Date().getFullYear();

// Mobile menu
const menuBtn = document.getElementById("menuBtn");
const navLinks = document.getElementById("navLinks");

menuBtn?.addEventListener("click", () => {
  navLinks.classList.toggle("open");
});

document.querySelectorAll(".nav-links a").forEach(link => {
  link.addEventListener("click", () => {
    navLinks.classList.remove("open");
  });
});

// Demo form → WhatsApp
document.getElementById("demoForm")?.addEventListener("submit", (e) => {
  e.preventDefault();

  const name = document.getElementById("name").value.trim();
  const company = document.getElementById("company").value.trim();
  const mobile = document.getElementById("mobile").value.trim();
  const email = document.getElementById("email").value.trim();
  const product = document.getElementById("product").value;
  const message = document.getElementById("message").value.trim();

  const text = `Rudra ERP — Demo Request
Name: ${name}
Company: ${company || "-"}
Mobile: ${mobile}
Email: ${email || "-"}
Product: ${product}
Message: ${message || "-"}`;

  // ⚠️ Replace with your real WhatsApp number (country code + number, no +)
  const whatsappNumber = "919999999999";
  window.open(`https://wa.me/${whatsappNumber}?text=${encodeURIComponent(text)}`, "_blank");
});
