// Gives a <video> a live canvas stream so it has real frames without media files.
function wire(id, color, play) {
  const v = document.getElementById(id);
  const c = document.createElement('canvas');
  c.width = 160; c.height = 90;
  const g = c.getContext('2d');
  let t = 0;
  setInterval(() => { g.fillStyle = color; g.fillRect(0, 0, 160, 90); g.fillStyle = '#fff'; g.fillText(id + ' ' + (t++), 8, 50); }, 100);
  v.srcObject = c.captureStream(10);
  if (play) v.play().catch(() => {});
}
