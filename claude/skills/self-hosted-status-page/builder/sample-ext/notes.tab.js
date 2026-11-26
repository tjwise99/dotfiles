(function notes(){const N=D.ext.notes,b=document.getElementById("notes-body");
 if(!N||!(N.paragraphs||[]).length){b.append(el("p",{class:"sub"},"No notes.json paragraphs in the data directory; this tab stays empty until its writer produces some."));return}
 document.getElementById("notes-sub").textContent=N.sub||"";
 N.paragraphs.forEach(p=>{b.append(el("h3",{},p.title||""),el("p",{},p.text||""),p.source?el("p",{class:"sub"},"Source: "+p.source):null)})})();
