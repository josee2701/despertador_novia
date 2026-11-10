const { chromium } = require('playwright');
const fs = require('fs');
const out = __dirname;
const head = fs.readFileSync(out + '/generar_imagenes.js', 'utf8').split('const slide =')[0];
const { css, status } = new Function('require', head + '; return {css,status};')(require);
const extra = `
.ts{position:relative;width:2560px;height:1440px;overflow:hidden;color:#fff}
.ts.a{background:#3a56b0}.ts.b{background:#0e1224}.ts.c{background:#e3e8f8;color:#141a2e}
.ts .txt{position:absolute;left:120px;top:0;bottom:0;width:700px;display:flex;flex-direction:column;justify-content:center}
.ts .txt h2{font-size:96px}.ts .txt p{font-size:36px}
.tab{position:absolute;left:860px;top:192px;width:1000px;height:640px;transform:scale(1.65);transform-origin:top left;border-radius:30px;border:9px solid #0a0d1b;background:var(--s);color:var(--ink);overflow:hidden;box-shadow:0 30px 80px rgba(0,0,0,.35);display:flex;flex-direction:column}
.tab.dk{border-color:#2f3768}
.body{flex:1;display:flex;position:relative;min-height:0}
.lp{width:370px;padding:6px 20px;overflow:hidden}
.rp{flex:1;margin:10px 20px 20px 0;background:var(--r);border-radius:28px;box-shadow:var(--sh);display:flex;flex-direction:column;align-items:center;justify-content:center;text-align:center}
.rp .lb2{font:700 12px/1 inherit;letter-spacing:1px;text-transform:uppercase;color:var(--mu)}
.rp .hero{font-weight:300;font-size:150px;line-height:150px;letter-spacing:-4px;margin:14px 0 6px}
.rp .hero small{font-size:32px;font-weight:600;color:var(--mu);letter-spacing:0}
.rp .pill{margin-top:22px;background:var(--bs);color:var(--b);font-weight:700;font-size:15px;padding:9px 18px;border-radius:99px}
.dim{position:absolute;inset:0;background:rgba(14,18,36,.5)}
.modal{position:absolute;left:50%;top:50%;transform:translate(-50%,-50%);width:430px;background:var(--r);border-radius:32px;padding:14px 24px 24px;box-shadow:0 30px 60px rgba(0,0,0,.3)}
`;
const cards = `
<div class="card"><div><div><span class="t">5:30</span><span class="m">AM</span></div><div class="mt">Trabajo · Lun–Vie</div></div><div class="sw"></div></div>
<div class="card"><div><div><span class="t">7:15</span><span class="m">AM</span><span class="hy">HOY</span></div><div class="mt">Gimnasio</div></div><div class="sw"></div></div>
<div class="card"><div><div><span class="t">6:00</span><span class="m">AM</span></div><div class="mt"><span class="dot"></span>Pospuesta · suena a las 6:05</div></div><div class="sw"></div></div>
<div class="card off"><div><div><span class="t">11:03</span><span class="m">AM</span></div><div class="mt">Fin de semana</div></div><div class="sw o"></div></div>`;
const left = `<div class="lp"><h1>Alarmas</h1><div class="clk">Lunes 10 de noviembre · 9:41 PM</div>${cards}</div>`;
const lista = `${status}<div class="body">${left}<div class="rp"><div class="lb2">Próxima alarma</div><div class="hero">5:30<small> AM</small></div><div style="font-weight:600;font-size:20px">Trabajo · Lun–Vie</div><div class="pill">Suena en 7 h 49 min</div></div></div>`;
const modal = (full) => `${status}<div class="body">${left}<div class="dim"></div><div class="modal"><div class="grip"></div><div class="big"><span class="t">6:45</span><span class="m">AM</span></div>
<div class="lb">Nombre</div><div class="fld">Gimnasio</div>
${full ? `<div class="lb">Repetir</div><div class="pl"><div class="p s">Lun–Vie</div><div class="p">Todos</div><div class="p">Fin de semana</div></div><div class="days"><div class="d s">L</div><div class="d s">M</div><div class="d s">X</div><div class="d s">J</div><div class="d s">V</div><div class="d">S</div><div class="d">D</div></div>` : ``}
<div class="btn">Guardar</div></div></div>`;
const sonando = `${status}<div class="body" style="align-items:center;justify-content:center"><div style="position:absolute;left:50%;top:50%;width:520px;height:520px;border-radius:50%;background:var(--r);transform:translate(-50%,-50%)"></div><div style="position:absolute;left:50%;top:50%;width:360px;height:360px;border-radius:50%;background:var(--bs);transform:translate(-50%,-50%)"></div>
<div style="position:relative;text-align:center"><div style="font-weight:700;font-size:24px">Trabajo</div><div style="font-size:14px;color:var(--mu);margin:4px 0 14px">Martes 11 de noviembre</div><span style="font-weight:300;font-size:110px;letter-spacing:-3px">5:30</span><span class="m" style="font-size:18px"> AM</span></div>
<div style="position:absolute;left:50%;bottom:34px;transform:translateX(-50%);width:420px"><div class="pista">Desliza para detener<i>→</i></div><div style="text-align:center;margin-top:14px;font-weight:600;font-size:15px">Posponer 5 min</div></div></div>`;
const slide = (cls, k, h, p, inner, dk) => `<div class="ts ${cls}"><div class="txt"><div class="k">${k}</div><h2>${h}</h2><p>${p}</p></div><div class="tab ${dk ? 'dk' : ''}">${inner}</div></div>`;
const html = `<html><head><meta charset=utf-8><link href="https://fonts.googleapis.com/css2?family=Manrope:wght@300;500;600;700;800&display=swap" rel="stylesheet"><style>${css}${extra}</style></head><body>
${slide('a', 'Bella Durmiente', 'Despierta con calma', 'Una app de alarmas simple, bonita y fácil de usar.', lista)}
${slide('c', 'Rápido', 'Crea una alarma en segundos', 'Elige la hora, toca Guardar y listo.', modal(false))}
${slide('a', 'Flexible', 'Repite justo los días que quieres', 'De lunes a viernes, fines de semana o todos los días.', modal(true))}
${slide('b', 'Sin complicaciones', 'Detén la alarma con un gesto', 'Desliza para detenerla o pospónla 5 minutos.', sonando, true)}
${slide('c', 'Para el día y la noche', 'Claro de día, oscuro de noche', 'Se adapta al tema de tu teléfono.', lista, true)}
</body></html>`;
(async () => {
  const b = await chromium.launch(); const pg = await b.newPage({ viewport: { width: 2600, height: 1500 } });
  await pg.setContent(html, { waitUntil: 'networkidle' }).catch(() => {});
  await pg.waitForTimeout(800);
  const names = ['tablet_01_lista', 'tablet_02_crear', 'tablet_03_repetir', 'tablet_04_detener', 'tablet_05_temas'];
  const el = await pg.$$('.ts');
  for (let i = 0; i < el.length; i++) await el[i].screenshot({ path: `${out}/${names[i]}.png` });
  await b.close();
})();
