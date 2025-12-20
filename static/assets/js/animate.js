// Make sure utility animations are included in stylesheet
// animate-1
// animate-2
// animate-3
// animate-4
// animate-5
// animate-6
// animate-7
// animate-8
// animate-9
// animate-10
// animate-11
// animate-12
// animate-13
// animate-14
// animate-15
// animate-16
// animate-17
// animate-18
// animate-19
// animate-20
// animate-21
// animate-22
// animate-23
// animate-24
// animate-25
// animate-26
// animate-27
// animate-28
// animate-29
// animate-30
// animate-31
// animate-32
// animate-33
// animate-34

/**
 * Animates the chars in p#subtext
 */
document.getElementById("subtext").innerHTML = Array.from(
  document.getElementById("subtext").innerText,
)
  .map((ch, i) => `<span class="animate-${i + 1}">${ch}</span>`)
  .join("");

let topBar = document.getElementById("topbar");
let bottomBar = document.getElementById("bottombar");

function mutate(element) {
  let newTxt = "";
  let length = window.innerWidth > 600 ? 50 : 20;
  for (let i = 0; i < length; ++i) {
    newTxt += Math.random() < 0.5 ? "\\" : "/";
  }
  element.textContent = newTxt;
}

// Run the mutation immediately for each existing element
if (topBar) mutate(topBar);
if (bottomBar) mutate(bottomBar);

// Then repeat every second
setInterval(function () {
  if (topBar) mutate(topBar);
  if (bottomBar) mutate(bottomBar);
}, 500);
