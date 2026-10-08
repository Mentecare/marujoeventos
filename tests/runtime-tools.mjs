import {createRequire} from 'node:module';
import os from 'node:os';
import path from 'node:path';
export const pdfTool=name=>process.env['EVENTCORE_'+name.toUpperCase()]||name;
export const python=process.env.EVENTCORE_PYTHON||'python3';
export const evidence=name=>path.join(os.tmpdir(),'eventcore-'+name);
export function browserRuntime(){
 const require=createRequire(import.meta.url);
 const {chromium}=require(process.env.EVENTCORE_PLAYWRIGHT_MODULE||'playwright');
 return {chromium,executablePath:process.env.EVENTCORE_CHROMIUM_EXECUTABLE||undefined};
}
