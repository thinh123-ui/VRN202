import assert from 'node:assert/strict';
import test from 'node:test';
import { readFileSync, existsSync } from 'node:fs';
import { calculateReward } from '../server/scoring.js';
import { missions, sourcedQuestions, events } from '../scripts/seed-data.js';

const documents=JSON.parse(readFileSync(new URL('../data/source-sessions.json',import.meta.url),'utf8'));
const docMap=new Map(documents.map(d=>[d.id,d]));

test('first full score receives question and completion rewards',()=>{
  assert.deepEqual(calculateReward(5,0,true),{xpEarned:235,coinsEarned:80});
});

test('replays cannot farm additional rewards without a new personal best',()=>{
  assert.deepEqual(calculateReward(3,4,false),{xpEarned:0,coinsEarned:0});
  assert.deepEqual(calculateReward(4,4,false),{xpEarned:0,coinsEarned:0});
  assert.deepEqual(calculateReward(5,4,false),{xpEarned:35,coinsEarned:10});
});

test('invalid reward inputs rejected',()=>{
  assert.throws(()=>calculateReward(-1,2,false),TypeError);
});

test('source corpus preserves 29 PDF sessions and 435 PDF pages',()=>{
  assert.equal(documents.length,29);
  assert.equal(documents.reduce((n,d)=>n+d.pages.length,0),435);
  assert.deepEqual(documents.map(d=>d.sessionNumber),Array.from({length:29},(_,i)=>i+1));
  assert.deepEqual([...new Set(documents.map(d=>d.chapterKey))].sort(),['chapter1','chapter2','chapter3','intro']);
  for(const d of documents){
    assert.ok(existsSync(new URL(`../public${d.filePath}`,import.meta.url)), `Missing PDF: ${d.filePath}`);
    assert.equal(d.pageCount,d.pages.length);
    assert.equal(d.pages[0].pageNumber,1);
    assert.equal(d.pages.at(-1).pageNumber,d.pageCount);
    assert.ok(d.pages.some(p=>p.content.length>30));
  }
});

test('six missions have ten questions each, correct metadata and unique answer order',()=>{
  assert.equal(missions.length,6);
  assert.equal(sourcedQuestions.length,60);
  assert.equal(new Set(missions.map(m=>m.slug)).size,missions.length);
  assert.deepEqual(missions.map(m=>m.sortOrder),[0,1,2,3,4,5]);
  assert.equal(new Set(sourcedQuestions.map(q=>q.id)).size,sourcedQuestions.length);
  for(const m of missions){
    const qq=sourcedQuestions.filter(q=>q.mission===m.slug);
    assert.equal(qq.length,10);
    assert.deepEqual(qq.map(q=>q.position),Array.from({length:10},(_,i)=>i+1));
    for(const q of qq){
      assert.equal(q.options.length,4);
      assert.equal(new Set(q.options).size,4);
      assert.ok(Number.isInteger(q.correct)&&q.correct>=0&&q.correct<4);
      assert.ok(q.explanation.length>15);
      const d=docMap.get(q.sourceDoc);
      assert.ok(d,`Unknown source document for ${q.id}`);
      assert.ok(d.pages[q.sourcePage-1],`Unknown source page for ${q.id}`);
    }
  }
});

test('timeline events preserve valid PDF provenance',()=>{
  assert.equal(events.length,13);
  assert.equal(new Set(events.map(e=>e[0])).size,13);
  for(const e of events){
    const d=docMap.get(e[7]);assert.ok(d);
    assert.ok(d.pages[e[8]-1]);
  }
});

import {course,chapters,buildLessons,buildFlashcards,achievements} from '../scripts/curriculum-data.js';
import {createHash} from 'node:crypto';
import {readFileSync as readBytes} from 'node:fs';

test('normalized VNR202 course has four chapters and 29 lessons linked to actual PDF sessions',()=>{
  assert.equal(course.code,'VNR202');
  assert.equal(chapters.length,4);
  const lessons=buildLessons(documents);
  assert.equal(lessons.length,29);
  assert.equal(new Set(lessons.map(x=>x.id)).size,29);
  for(const item of lessons){
    const source=docMap.get(item.documentId);
    assert.ok(source);
    assert.equal(source.sessionNumber,item.sessionNumber);
    assert.ok(chapters.some(c=>c.key===item.chapterKey));
  }
});

test('60 flashcards have real PDF sources and exact quiz answers',()=>{
  const cards=buildFlashcards(sourcedQuestions);
  assert.equal(cards.length,60);
  assert.equal(new Set(cards.map(c=>c.id)).size,60);
  for (const card of cards){
    const question=sourcedQuestions.find(q=>q.id===card.questionId);
    assert.ok(question);
    assert.equal(card.back,question.options[question.correct]);
    assert.equal(card.sourceDocumentId,question.sourceDoc);
    assert.ok(docMap.get(card.sourceDocumentId).pages[card.sourcePage-1]);
  }
  assert.equal(achievements.length,4);
});

test('stored PDF SHA-256 checksums match included original PDFs',()=>{
  for(const d of documents){
    const bytes=readBytes(new URL(`../public${d.filePath}`,import.meta.url));
    assert.equal(createHash('sha256').update(bytes).digest('hex'),d.sha256,`SHA mismatch ${d.fileName}`);
  }
});

test('import template has valid new question with grounded source',()=>{
  const imports=JSON.parse(readFileSync(new URL('../data/questions-import-template.json',import.meta.url),'utf8'));
  assert.equal(imports.length,1);
  assert.ok(!sourcedQuestions.some(q=>q.id===imports[0].id));
  assert.ok(docMap.get(imports[0].sourceDocumentId).pages[imports[0].sourcePage-1]);
  assert.equal(imports[0].options.length,4);
  assert.ok(imports[0].correctIndex>=0 && imports[0].correctIndex<4);
});
