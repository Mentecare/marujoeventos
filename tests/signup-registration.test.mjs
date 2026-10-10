import test from "node:test";
import assert from "node:assert/strict";
import { validateSignup } from "../lib/signup-registration.ts";
const base={email:" SignUp@Example.com ",password:"reliable-Strong123",payload:{
  profile_type:"freelancer",full_name:"Exemplo Freelancer",phone:"21999999999",document_type:"cpf",
  document_number:"529.982.247-25",specialty_ids:["a5b544c8-6e1c-4f4b-a458-34286120fa40"],
  organization_name:"",business_type:"",city:"Rio de Janeiro",bio:"",professional_status:"available"
}};
test("private registration validates and normalizes a complete freelancer registration",()=>{
 const data=validateSignup(base);assert.ok(data);assert.equal(data.email,"signup@example.com");
 assert.equal(data.payload.document_number,"52998224725");assert.deepEqual(data.payload.specialty_ids,base.payload.specialty_ids);
});
test("invalid or duplicate data never makes it to storage",()=>{
 assert.equal(validateSignup({...base,payload:{...base.payload,document_number:"00000000000"}}),null);
 assert.equal(validateSignup({...base,payload:{...base.payload,specialty_ids:[base.payload.specialty_ids[0],base.payload.specialty_ids[0]]}}),null);
 assert.equal(validateSignup({...base,payload:{...base.payload,profile_type:"company"}}),null);
});
test("business profiles require an organization and a valid market activity",()=>{
 assert.equal(validateSignup({...base,payload:{...base.payload,profile_type:"team_lead"}}),null);
 const team={...base,payload:{...base.payload,profile_type:"team_lead",organization_name:"Equipe de Produção",market_role:"provider"}};
 assert.equal(validateSignup(team)?.payload.market_role,"provider");
 assert.equal(validateSignup({...team,payload:{...team.payload,market_role:"buyer"}}),null);
});
