const year = document.getElementById("year");
if (year) year.textContent = new Date().getFullYear();

const menu = document.querySelector(".menu-toggle");
const nav = document.querySelector(".main-nav");

menu?.addEventListener("click", () => {
  const open = nav.classList.toggle("open");
  menu.setAttribute("aria-expanded", String(open));
});

document.querySelectorAll(".main-nav a").forEach(link => {
  link.addEventListener("click", () => {
    nav.classList.remove("open");
    menu?.setAttribute("aria-expanded", "false");
  });
});

document.getElementById("demoForm")?.addEventListener("submit", event => {
  event.preventDefault();

  const name = document.getElementById("name").value.trim();
  const company = document.getElementById("company").value.trim();
  const mobile = document.getElementById("mobile").value.trim();
  const email = document.getElementById("email").value.trim();
  const product = document.getElementById("product").value;
  const message = document.getElementById("message").value.trim();

  const text = `Rudra Digital Solutions — Demo Request
Name: ${name}
Company: ${company || "-"}
Mobile: ${mobile}
Email: ${email || "-"}
Product: ${product}
Message: ${message || "-"}`;

  // IMPORTANT: replace this placeholder with the real WhatsApp number.
  const whatsappNumber = "919999999999";
  window.open(`https://wa.me/${whatsappNumber}?text=${encodeURIComponent(text)}`, "_blank");
});
