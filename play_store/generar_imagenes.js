const { chromium } = require('playwright');
const path = require('path');
const out = '.';
const css = `
:root{--s:#f5f6fb;--r:#fff;--sk:#eceff7;--ink:#141a2e;--mu:#565e7c;--fa:#7a829f;--b:#3a56b0;--ob:#fff;--bs:#e3e8f8;--ac:#f2b84b;--sh:0 1px 2px rgba(20,26,46,.05),0 8px 24px rgba(20,26,46,.08)}
.dk{--s:#0e1224;--r:#171c34;--sk:#0a0d1b;--ink:#eef1fb;--mu:#a3abc8;--fa:#6b7399;--b:#8fa6ff;--ob:#0e1224;--bs:#232b52;--ac:#f2c46d;--sh:0 1px 2px rgba(0,0,0,.3),0 8px 24px rgba(0,0,0,.35)}
*{box-sizing:border-box}body{margin:0;font-family:Manrope,'Segoe UI',system-ui,sans-serif}
.slide{position:relative;width:1080px;height:1920px;overflow:hidden;color:#fff}
.slide.a{background:#3a56b0}.slide.b{background:#0e1224}.slide.c{background:#e3e8f8;color:#141a2e}
.txt{position:absolute;left:80px;right:80px;top:110px}
.txt .k{font:700 30px/1 inherit;letter-spacing:3px;text-transform:uppercase;opacity:.8;margin-bottom:28px}
.txt h2{margin:0;font-weight:800;font-size:104px;line-height:1.02;letter-spacing:-3px}
.txt p{margin:28px 0 0;font-weight:500;font-size:38px;line-height:1.35;opacity:.85}
.phone{position:absolute;left:50%;top:620px;width:360px;height:760px;transform:translateX(-50%) scale(2.3);transform-origin:top center;border-radius:44px;border:7px solid #0a0d1b;background:var(--s);color:var(--ink);overflow:hidden;box-shadow:0 30px 80px rgba(0,0,0,.35)}
.sb{height:28px;display:flex;justify-content:space-between;padding:8px 22px 0;font:700 11px/1 inherit}
.pad{padding:12px 20px}
h1{margin:0;font-weight:800;font-size:34px;line-height:40px;letter-spacing:-.5px}
.clk{font-weight:500;font-size:13px;color:var(--mu);margin:4px 0 14px}
.res{display:flex;gap:12px;align-items:center;padding:12px;background:var(--bs);border-radius:16px;margin-bottom:14px}
.res i{width:36px;height:36px;border-radius:50%;background:var(--r);display:grid;place-items:center;color:var(--b);font-style:normal;font-weight:800}
.res b{display:block;font-weight:600;font-size:15px}.res span{font-size:12px;color:var(--mu);font-weight:500}
.card{display:flex;justify-content:space-between;align-items:center;padding:14px 18px;background:var(--r);border-radius:24px;box-shadow:var(--sh);margin-bottom:11px}
.card.off{background:var(--sk);box-shadow:none}
.t{font-weight:300;font-size:44px;line-height:48px;letter-spacing:-1px}.m{font-weight:600;font-size:15px;color:var(--mu);margin-left:4px}
.card.off .t{color:var(--mu)}
.mt{font-weight:500;font-size:12px;color:var(--mu);display:flex;gap:6px;align-items:center}.dot{width:7px;height:7px;border-radius:50%;background:var(--ac)}
.hy{font:700 11px/1 inherit;background:var(--bs);color:var(--b);border-radius:99px;padding:3px 8px;margin-left:8px;letter-spacing:.4px;vertical-align:middle}
.sw{width:50px;height:30px;border-radius:99px;position:relative;background:var(--b)}.sw:after{content:"";position:absolute;top:4px;left:24px;width:22px;height:22px;border-radius:50%;background:var(--ob)}
.sw.o{background:none;border:2px solid var(--fa)}.sw.o:after{top:5px;left:5px;width:16px;height:16px;background:var(--fa)}
.fab{position:absolute;right:18px;bottom:20px;height:54px;padding:0 22px;border-radius:99px;background:var(--b);color:var(--ob);font-weight:600;font-size:15px;display:flex;align-items:center;gap:8px;box-shadow:0 12px 32px rgba(58,86,176,.35)}
.sheet{position:absolute;left:0;right:0;bottom:0;background:var(--r);border-radius:32px 32px 0 0;padding:12px 22px 22px;box-shadow:0 -10px 40px rgba(0,0,0,.18)}
.grip{width:36px;height:4px;border-radius:2px;background:var(--fa);margin:0 auto 12px}
.big{display:flex;justify-content:center;align-items:baseline;gap:6px;background:var(--bs);border-radius:16px;padding:12px}.big .t{font-size:62px;line-height:66px}
.lb{font:700 11px/1 inherit;letter-spacing:.4px;text-transform:uppercase;color:var(--mu);margin:16px 0 8px}
.fld{height:48px;background:var(--sk);border-radius:12px;padding:0 14px;display:flex;align-items:center;font-weight:500;font-size:14px}
.days{display:flex;gap:6px}.d{width:38px;height:38px;border-radius:50%;border:2px solid var(--fa);display:grid;place-items:center;font-weight:700;font-size:13px}.d.s{background:var(--b);border-color:var(--b);color:var(--ob)}
.pl{display:flex;gap:8px;margin-bottom:12px}.p{height:34px;padding:0 14px;border-radius:99px;border:2px solid var(--fa);font-weight:600;font-size:12px;display:grid;place-items:center}.p.s{background:var(--bs);border-color:var(--b);color:var(--b)}
.btn{margin-top:18px;height:50px;border-radius:99px;background:var(--b);color:var(--ob);display:grid;place-items:center;font-weight:600;font-size:15px}
.ring{position:absolute;left:50%;top:260px;border-radius:50%;transform:translate(-50%,-50%)}
.pista{position:relative;height:60px;border-radius:99px;background:var(--bs);display:grid;place-items:center;font-weight:600;font-size:14px;color:var(--mu)}.pista i{position:absolute;left:4px;top:4px;width:52px;height:52px;border-radius:50%;background:var(--b);color:var(--ob);display:grid;place-items:center;font-style:normal;font-size:22px}
.phone.fit{height:640px;top:560px;transform:translateX(-50%) scale(2.1)}.dk.phone{border-color:#2f3768}.feat{position:relative;width:1024px;height:500px;background:#3a56b0;color:#fff;overflow:hidden}
.feat .ico{position:absolute;right:70px;top:50px;width:400px;height:400px;filter:drop-shadow(0 20px 40px rgba(0,0,0,.35))}
.feat h2{position:absolute;left:64px;top:120px;margin:0;font-weight:800;font-size:92px;line-height:.98;letter-spacing:-2.5px}
.feat p{position:absolute;left:64px;top:340px;margin:0;font-weight:500;font-size:30px;opacity:.9;width:480px;line-height:1.3}
`;
const status = `<div class="sb"><span>9:41</span><span>5G ▮▮▮</span></div>`;
const cards = `
<div class="card"><div><span class="t">5:30</span><span class="m">AM</span></div><div class="sw"></div></div>`;
const lista = (dark) => `${status}<div class="pad"><h1>Alarmas</h1><div class="clk">Lunes 10 de noviembre · 9:41 PM</div>
<div class="res"><i>⏰</i><div><b>Suena en 7 h 49 min</b><span>Mañana · 5:30 AM · Trabajo</span></div></div>
<div class="card"><div><div><span class="t">5:30</span><span class="m">AM</span></div><div class="mt">Trabajo · Lun–Vie</div></div><div class="sw"></div></div>
<div class="card"><div><div><span class="t">7:15</span><span class="m">AM</span><span class="hy">HOY</span></div><div class="mt">Gimnasio</div></div><div class="sw"></div></div>
<div class="card"><div><div><span class="t">6:00</span><span class="m">AM</span></div><div class="mt"><span class="dot"></span>Pospuesta · suena a las 6:05</div></div><div class="sw"></div></div>
<div class="card off"><div><div><span class="t">11:03</span><span class="m">AM</span></div><div class="mt">Fin de semana</div></div><div class="sw o"></div></div></div>
<div class="fab">＋ Nueva alarma</div>`;
const hoja = (completo) => `${status}<div class="pad"><h1>Alarmas</h1><div class="clk">Lunes 10 de noviembre · 9:41 PM</div>
<div class="card" style="opacity:.5"><div><span class="t">5:30</span><span class="m">AM</span></div><div class="sw"></div></div></div>
<div style="position:absolute;inset:0;background:rgba(14,18,36,.45)"></div>
<div class="sheet"><div class="grip"></div><div class="big"><span class="t">6:45</span><span class="m">AM</span></div>
<div class="lb">Nombre</div><div class="fld">Gimnasio</div>
${completo ? `<div class="lb">Repetir</div><div class="pl"><div class="p s">Lun–Vie</div><div class="p">Todos</div><div class="p">Fin de semana</div></div>
<div class="days"><div class="d s">L</div><div class="d s">M</div><div class="d s">X</div><div class="d s">J</div><div class="d s">V</div><div class="d">S</div><div class="d">D</div></div>` : ``}
<div class="btn">Guardar</div></div>`;
const sonando = `${status}<div class="ring" style="width:420px;height:420px;background:var(--r)"></div><div class="ring" style="width:290px;height:290px;background:var(--bs)"></div>
<div style="position:relative;text-align:center;padding-top:50px"><div style="font-weight:700;font-size:22px">Trabajo</div><div style="font-size:13px;color:var(--mu);margin-top:4px">Martes 11 de noviembre</div>
<div style="margin-top:110px"><span style="font-weight:300;font-size:88px;letter-spacing:-2px">5:30</span><span class="m" style="font-size:16px"> AM</span></div></div>
<div style="position:absolute;left:24px;right:24px;bottom:34px"><div class="pista">Desliza para detener<i>→</i></div><div style="text-align:center;margin-top:18px;font-weight:600;font-size:15px">Posponer 5 min</div></div>`;
const slide = (cls, k, h, p, inner, dk, fit) => `<div class="slide ${cls}"><div class="txt"><div class="k">${k}</div><h2>${h}</h2><p>${p}</p></div><div class="phone ${dk?'dk':''} ${fit?'fit':''}">${inner}</div></div>`;
const html = `<html><head><meta charset=utf-8><link href="https://fonts.googleapis.com/css2?family=Manrope:wght@300;500;600;700;800&display=swap" rel="stylesheet"><style>${css}</style></head><body>
${slide('a','Bella Durmiente','Despierta con calma','Una app de alarmas simple, bonita y fácil de usar.',lista())}
${slide('c','Rápido','Crea una alarma en segundos','Elige la hora, toca Guardar y listo.',hoja(false),false,true)}
${slide('a','Flexible','Repite justo los días que quieres','De lunes a viernes, fines de semana o todos los días.',hoja(true),false,true)}
${slide('b','Sin complicaciones','Detén la alarma con un gesto','Desliza para detenerla o pospónla 5 minutos.',sonando,true,true)}
${slide('c','Para el día y la noche','Claro de día, oscuro de noche','Se adapta al tema de tu teléfono.',lista(),true)}
<div class="feat"><img class="ico" src="data:image/png;base64,${require('fs').readFileSync(out+'/icono_app.png').toString('base64')}"><h2>Bella<br>Durmiente</h2><p>Despierta con calma.</p></div>
</body></html>`;
(async () => {
  const b = await chromium.launch(); const pg = await b.newPage({ viewport: { width: 1100, height: 2000 } });
  await pg.setContent(html, { waitUntil: 'networkidle' }).catch(()=>{});
  await pg.waitForTimeout(800);
  const names = ['01_lista','02_crear','03_repetir','04_detener','05_temas'];
  const slides = await pg.$$('.slide');
  // slide 5: show dark list side: wrap handled below
  for (let i=0;i<slides.length;i++) await slides[i].screenshot({ path: `${out}/${names[i]}.png` });
  await (await pg.$('.feat')).screenshot({ path: `${out}/grafico_destacado.png` });
  await b.close();
})();
