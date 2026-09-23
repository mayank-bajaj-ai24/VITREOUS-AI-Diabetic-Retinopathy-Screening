import fs from 'node:fs/promises';
import path from 'node:path';
import { pathToFileURL } from 'node:url';
import { Presentation, PresentationFile } from '@oai/artifact-tool';

const workspaceDir = 'C:/Users/Chait/OneDrive/Desktop/simulink/DR_Screening_Capacity_Model';
const skillDir = 'C:/Users/Chait/.codex/plugins/cache/openai-primary-runtime/presentations/26.905.11957/skills/presentations';
const runtimePython = 'C:/Users/Chait/.cache/codex-runtimes/codex-primary-runtime/dependencies/python/python.exe';
const buildDir = path.join(workspaceDir, '.build_deck');
const finalPath = path.join(workspaceDir, 'deliverables', 'SIH_DR_Capacity_Model_Demo.pptx');
const { resolvePresentationFont, finalizePresentation } = await import(pathToFileURL(path.join(skillDir, 'container_tools/artifact_tool_utils.mjs')).href);
const font = resolvePresentationFont({ fontFamily: 'Aptos' });
const deck = Presentation.create({slideSize:{width:1280,height:720}});
const navy='#102A43', blue='#1877B9', teal='#0F766E', pale='#F4F8FB', ink='#1D2939';
const img = async n => new Uint8Array(await fs.readFile(path.join(workspaceDir,'results',n)));
function text(slide, value, left, top, width, height, size=24, color=ink, bold=false) {
  const s=slide.shapes.add({geometry:'textbox',position:{left,top,width,height},fill:'none',line:{fill:'none',width:0}});
  s.text=value; s.text.style={typeface:font,fontSize:size,color,bold,autoFit:'shrinkText'}; return s;
}
function base(title) { const s=deck.slides.add(); s.background.fill=pale; text(s,title,64,42,1152,50,32,navy,true); return s; }
function addImage(s,bytes,alt,left,top,width,height){s.images.add({blob:bytes,contentType:'image/png',alt,fit:'contain',position:{left,top,width,height}});}

let s=deck.slides.add(); s.background.fill=navy;
text(s,'DR Screening District Capacity Model',72,130,850,68,42,'#FFFFFF',true);
text(s,'SimEvents operational capacity model for rural screening deployment',72,215,770,42,24,'#D7E9F7');
text(s,'SIH 2026 demo package',72,570,360,30,19,'#B9D8EE');

s=base('Operational model architecture');
text(s,'Patient flow models capture, quality recapture, AI routing, review capacity, and deferred image sync.',64,105,1090,36,20);
text(s,'Clinical performance remains external telemetry. The model evaluates operational queues and capacity only.',64,150,1090,36,18,teal,true);
const architecture = [
  ['Patient arrivals','Camera queue','Quality recapture','AI routing','Review / auto-clear'],
  ['Processed image copy','Local sync queue','Connectivity gate','Bandwidth server','District server']
];
architecture.forEach((row,r)=>row.forEach((label,c)=>{const x=68+c*235,y=245+r*190;const sh=s.shapes.add({geometry:'roundRect',position:{left:x,top:y,width:190,height:76},fill:{color:r? '#DDF4F0':'#DCEEFF'},line:{fill:blue,width:1}});sh.text=label;sh.text.style={typeface:font,fontSize:18,bold:true,color:navy,autoFit:'shrinkText'}; if(c<4){const ln=s.shapes.add({geometry:'line',position:{left:x+191,top:y+38,width:38,height:0},line:{fill:blue,width:2,beginArrowType:'none',endArrowType:'triangle'}});}}));

s=base('Current simulation summary');
addImage(s,await img('dashboard_summary.png'),'Summary dashboard with AI workload, confidence, bandwidth, and utilization charts',64,115,1152,540);

s=base('Confidence and quality scenarios');
addImage(s,await img('threshold_sweep.png'),'Confidence threshold sweep',55,125,560,500);
addImage(s,await img('resource_sweeps.png'),'Camera, ophthalmologist, and quality rejection sweeps',650,125,560,500);
text(s,'Higher routing threshold increases simulated referral volume. Higher rejection raises camera attempts.',64,645,1120,26,17,teal,true);

s=base('Bandwidth and minimum configuration');
addImage(s,await img('bandwidth_sweep.png'),'Bandwidth versus deferred-sync backlog',64,125,560,470);
text(s,'Minimum feasible configuration under current illustrative assumptions',680,145,470,36,24,navy,true);
text(s,'1 camera\n1 ophthalmologist\n5 Mbps bandwidth\n399 patients per camp\n0 end-of-camp sync backlog',710,220,400,260,27,ink,false);
text(s,'Replace config.m placeholders with measured field telemetry before making deployment claims.',680,540,460,58,18,teal,true);
text(s,'Demo: AI-OFF vs AI-ON, quality rejection, low bandwidth, restored connectivity, then resource recommendation.',64,640,1100,28,17,blue,true);

const candidatePath=path.join(buildDir,'candidate.pptx');
await (await PresentationFile.exportPptx(deck)).save(candidatePath);
await finalizePresentation({workspaceDir,candidatePath,finalPath,pythonExecutable:runtimePython,integrityValidatorPath:path.join(skillDir,'container_tools/inspect_presentation_package_integrity.py'),layoutValidatorPath:path.join(skillDir,'container_tools/inspect_presentation_layout_geometry.py'),layoutArgs:['--expected-slide-size-emu','12192000,6858000','--validate-bullet-geometry','--validate-heading-fit'],fontPolicy:{basis:'design',families:[font]},verifyArtifactToolImport:true,receiptPath:path.join(buildDir,'validation.json')});
