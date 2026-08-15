document.getElementById("year").textContent = new Date().getFullYear();

const menu = document.querySelector(".menu");
const nav = document.querySelector("nav");
menu?.addEventListener("click", () => {
  const open = nav.style.display === "flex";
  nav.style.display = open ? "" : "flex";
  nav.style.flexDirection = "column";
  nav.style.position = "absolute";
  nav.style.top = "70px";
  nav.style.right = "5%";
  nav.style.padding = "18px";
  nav.style.background = "#0b2135";
  nav.style.border = "1px solid rgba(255,255,255,.1)";
  nav.style.borderRadius = "14px";
});

document.querySelectorAll("nav a").forEach(a => a.addEventListener("click", () => {
  if (window.innerWidth <= 900) nav.style.display = "";
}));

document.getElementById("demoForm")?.addEventListener("submit", e => {
  e.preventDefault();
  const name = document.getElementById("name").value.trim();
  const company = document.getElementById("company").value.trim();
  const mobile = document.getElementById("mobile").value.trim();
  const email = document.getElementById("email").value.trim();
  const product = document.getElementById("product").value;
  const message = document.getElementById("message").value.trim();

  const text =
`Rudra Demo Request
Name: ${name}
Company: ${company || "-"}
Mobile: ${mobile}
Email: ${email || "-"}
Product: ${product}
Message: ${message || "-"}`;

  // Replace 919999999999 with your WhatsApp number including country code.
  const whatsappNumber = "919999999999";
  window.open(`https://wa.me/${whatsappNumber}?text=${encodeURIComponent(text)}`, "_blank");
});
