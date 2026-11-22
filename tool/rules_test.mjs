// 파이어베이스 규칙 시험 (코드 점검 때 가짜 저장소에서 돌림): 후기·사진·신고가 막혀야 할 것은 막히고 되는 것은 되는지
import { initializeTestEnvironment, assertSucceeds, assertFails } from '@firebase/rules-unit-testing';
import { doc, setDoc, updateDoc, deleteDoc, getDoc, getDocs, collection, query, where, serverTimestamp, arrayUnion, arrayRemove, increment, setLogLevel } from 'firebase/firestore';
import { readFileSync } from 'node:fs';

setLogLevel('error');
const env = await initializeTestEnvironment({
  projectId: 'demo-kokple',
  firestore: { rules: readFileSync(process.env.RULES || 'firestore.rules', 'utf8') },
});

const kday = (shiftDays = 0) => {
  const k = new Date(Date.now() + 9 * 3600 * 1000 + shiftDays * 86400 * 1000);
  return k.getUTCFullYear() * 10000 + (k.getUTCMonth() + 1) * 100 + k.getUTCDate();
};
const alice = env.authenticatedContext('alice', { email: 'a@test.com' }).firestore();
const bob = env.authenticatedContext('bob', { email: 'b@test.com' }).firestore();
const admin = env.authenticatedContext('boss', { email: 'dfmail@naver.com', email_verified: true }).firestore();
const nobody = env.unauthenticatedContext().firestore();

const day = kday();
const review = (uid, extra = {}) => ({
  uid, nick: '콕플러 1234', pid: '13635514', pname: '군봉묵은지김치찜', rec: { id: '13635514', n: '군봉묵은지김치찜', a: 'songdo' },
  st: ['again', 'value'], menu: '', star: 4, text: '또 올게요', ph: 0, th: [], likes: [], lc: 0, hidden: false,
  at: serverTimestamp(), day, ...extra,
});
const rid = (uid, d = day, pid = '13635514') => `${pid}_${uid}_${d}`;

let n = 0, bad = 0;
async function t(name, p) {
  n++;
  try {
    await p;
    console.log('통과', name);
  } catch (e) {
    bad++;
    console.log('실패', name, '—', (e && e.message) || e);
  }
}

await t('비회원도 후기 읽기', assertSucceeds(getDoc(doc(nobody, 'reviews', 'x'))));
await t('알맞은 후기 쓰기', assertSucceeds(setDoc(doc(alice, 'reviews', rid('alice')), review('alice'))));
await t('같은 가게 같은 날 두 번째 → 막힘', assertFails(setDoc(doc(alice, 'reviews', rid('alice')), review('alice'))));
await t('남의 이름으로 쓰기 → 막힘', assertFails(setDoc(doc(bob, 'reviews', rid('alice', day, '1')), review('alice', { pid: '1' }))));
await t('비회원 쓰기 → 막힘', assertFails(setDoc(doc(nobody, 'reviews', rid('nobody', day, '2')), review('nobody', { pid: '2' }))));
await t('스티커 6개 → 막힘', assertFails(setDoc(doc(bob, 'reviews', rid('bob', day, '3')), review('bob', { pid: '3', st: ['again', 'value', 'big', 'solo', 'date', 'kind'] }))));
await t('없는 스티커 → 막힘', assertFails(setDoc(doc(bob, 'reviews', rid('bob', day, '4')), review('bob', { pid: '4', st: ['broadcast'] }))));
await t('같은 스티커 두 번 → 막힘', assertFails(setDoc(doc(bob, 'reviews', rid('bob', day, '5')), review('bob', { pid: '5', st: ['again', 'again'] }))));
await t('스티커 없음 → 막힘', assertFails(setDoc(doc(bob, 'reviews', rid('bob', day, '6')), review('bob', { pid: '6', st: [] }))));
await t('메뉴 스티커인데 메뉴 이름 없음 → 막힘', assertFails(setDoc(doc(bob, 'reviews', rid('bob', day, '7')), review('bob', { pid: '7', st: ['menu'] }))));
await t('메뉴 스티커 + 메뉴 이름 → 됨', assertSucceeds(setDoc(doc(bob, 'reviews', rid('bob', day, '8')), review('bob', { pid: '8', st: ['menu', 'life'], menu: '김치찜' }))));
await t('지금도 맛있어요 스티커 → 됨', assertSucceeds(setDoc(doc(bob, 'reviews', rid('bob', day, '9')), review('bob', { pid: '9', st: ['still', 'again'] }))));
await t('예전만 못해요 스티커 → 됨', assertSucceeds(setDoc(doc(bob, 'reviews', rid('bob', day, '10')), review('bob', { pid: '10', st: ['worse'] }))));
await t('어제 날짜 → 됨 (밤 12시 언저리)', assertSucceeds(setDoc(doc(bob, 'reviews', rid('bob', kday(-1), '9')), review('bob', { pid: '9', day: kday(-1) }))));
await t('그저께 날짜 → 막힘', assertFails(setDoc(doc(bob, 'reviews', rid('bob', kday(-2), '10')), review('bob', { pid: '10', day: kday(-2) }))));
await t('문서 이름과 날짜가 다름 → 막힘', assertFails(setDoc(doc(bob, 'reviews', rid('bob', kday(-1), '11')), review('bob', { pid: '11' }))));
await t('공감 수를 미리 넣고 쓰기 → 막힘', assertFails(setDoc(doc(bob, 'reviews', rid('bob', day, '12')), review('bob', { pid: '12', likes: ['x'], lc: 1 }))));
await t('숨김 풀린 척 → 막힘', assertFails(setDoc(doc(bob, 'reviews', rid('bob', day, '13')), review('bob', { pid: '13', hidden: true }))));
await t('한 줄 평 81자 → 막힘', assertFails(setDoc(doc(bob, 'reviews', rid('bob', day, '14')), review('bob', { pid: '14', text: '가'.repeat(81) }))));
await t('사진 수와 작은 사진 수가 다름 → 막힘', assertFails(setDoc(doc(bob, 'reviews', rid('bob', day, '15')), review('bob', { pid: '15', ph: 2, th: ['a'] }))));
await t('사진 2장 → 됨', assertSucceeds(setDoc(doc(bob, 'reviews', rid('bob', day, '16')), review('bob', { pid: '16', ph: 2, th: ['a', 'b'] }))));
await t('별점 6 → 막힘', assertFails(setDoc(doc(bob, 'reviews', rid('bob', day, '17')), review('bob', { pid: '17', star: 6 }))));
await t('모르는 칸 넣기 → 막힘', assertFails(setDoc(doc(bob, 'reviews', rid('bob', day, '18')), review('bob', { pid: '18', admin: true }))));

const ar = doc(bob, 'reviews', rid('alice'));
await t('공감 누르기 → 됨', assertSucceeds(updateDoc(ar, { likes: arrayUnion('bob'), lc: increment(1) })));
await t('공감 또 누르기(수만 올리기) → 막힘', assertFails(updateDoc(ar, { likes: arrayUnion('bob'), lc: increment(1) })));
await t('남의 공감 넣기 → 막힘', assertFails(updateDoc(ar, { likes: arrayUnion('carol'), lc: increment(1) })));
await t('공감하며 글 고치기 → 막힘', assertFails(updateDoc(ar, { text: '바꿈' })));
await t('공감 빼기 → 됨', assertSucceeds(updateDoc(ar, { likes: arrayRemove('bob'), lc: increment(-1) })));
await t('공감 수 마음대로 → 막힘', assertFails(updateDoc(ar, { lc: 100 })));

const mine = doc(alice, 'reviews', rid('alice'));
await t('내 후기 고치기 → 됨', assertSucceeds(updateDoc(mine, { text: '고쳤어요', st: ['life'], ed: serverTimestamp() })));
await t('고칠 때 시각 표시 빠짐 → 막힘', assertFails(updateDoc(mine, { text: '또 고침' })));
await t('내 후기 공감 수 바꾸기 → 막힘', assertFails(updateDoc(mine, { lc: 5, likes: ['a', 'b', 'c', 'd', 'e'], ed: serverTimestamp() })));
await t('관리자 숨기기 → 됨', assertSucceeds(updateDoc(doc(admin, 'reviews', rid('alice')), { hidden: true })));
await t('내 후기 숨김 풀기 → 막힘', assertFails(updateDoc(mine, { hidden: false, ed: serverTimestamp() })));
await t('남의 후기 지우기 → 막힘', assertFails(deleteDoc(doc(bob, 'reviews', rid('alice')))));

const img = (uid, r, i) => ({ uid, rid: r, d: 'data' + i });
await t('내 후기 사진 올리기 → 됨', assertSucceeds(setDoc(doc(alice, 'reviewImg', `${rid('alice')}_0`), img('alice', rid('alice'), 0))));
await t('내 후기 사진 바꾸기 → 됨', assertSucceeds(setDoc(doc(alice, 'reviewImg', `${rid('alice')}_0`), img('alice', rid('alice'), 9))));
await t('4번째 사진 → 막힘', assertFails(setDoc(doc(alice, 'reviewImg', `${rid('alice')}_3`), img('alice', rid('alice'), 3))));
await t('남의 후기에 사진 → 막힘', assertFails(setDoc(doc(bob, 'reviewImg', `${rid('alice')}_1`), img('bob', rid('alice'), 1))));
await t('남의 사진 덮어쓰기 → 막힘', assertFails(setDoc(doc(bob, 'reviewImg', `${rid('alice')}_0`), img('bob', rid('bob'), 0))));
await t('사진 읽기(비회원) → 됨', assertSucceeds(getDoc(doc(nobody, 'reviewImg', `${rid('alice')}_0`))));
await t('남의 사진 지우기 → 막힘', assertFails(deleteDoc(doc(bob, 'reviewImg', `${rid('alice')}_0`))));
await t('내 사진 지우기 → 됨', assertSucceeds(deleteDoc(doc(alice, 'reviewImg', `${rid('alice')}_0`))));

const rep = { uid: 'bob', rid: rid('alice'), why: '광고·홍보', pname: '군봉묵은지김치찜', text: '고쳤어요', at: serverTimestamp() };
await t('신고하기 → 됨', assertSucceeds(setDoc(doc(bob, 'reports', `${rid('alice')}_bob`), rep)));
await t('같은 후기 두 번 신고 → 막힘', assertFails(setDoc(doc(bob, 'reports', `${rid('alice')}_bob`), rep)));
await t('남의 이름으로 신고 → 막힘', assertFails(setDoc(doc(alice, 'reports', `${rid('bob', day, '8')}_bob`), { ...rep, rid: rid('bob', day, '8') })));
await t('신고 목록 엿보기 → 막힘', assertFails(getDocs(collection(alice, 'reports'))));
await t('관리자 신고 목록 → 됨', assertSucceeds(getDocs(collection(admin, 'reports'))));
await t('내 신고만 모아 보기 → 됨', assertSucceeds(getDocs(query(collection(bob, 'reports'), where('uid', '==', 'bob')))));
await t('관리자 신고 지우기 → 됨', assertSucceeds(deleteDoc(doc(admin, 'reports', `${rid('alice')}_bob`))));

await t('내 후기 지우기 → 됨', assertSucceeds(deleteDoc(doc(alice, 'reviews', rid('alice')))));
const carol = env.authenticatedContext('carol', { email: 'c@test.com' }).firestore();
await t('관리자가 아닌데 쓰기 막기 → 막힘', assertFails(setDoc(doc(bob, 'bans', 'carol'), { why: 'x' })));
await t('관리자 쓰기 막기 → 됨', assertSucceeds(setDoc(doc(admin, 'bans', 'carol'), { why: '광고', at: serverTimestamp() })));
await t('막힌 회원 후기 쓰기 → 막힘', assertFails(setDoc(doc(carol, 'reviews', rid('carol', day, '20')), review('carol', { pid: '20' }))));
await t('막힌 회원 사진 올리기 → 막힘', assertFails(setDoc(doc(carol, 'reviewImg', `${rid('carol', day, '20')}_0`), img('carol', rid('carol', day, '20'), 0))));
await t('막힌 회원 자기 막힘 확인 → 됨', assertSucceeds(getDoc(doc(carol, 'bans', 'carol'))));
await t('남의 막힘 엿보기 → 막힘', assertFails(getDoc(doc(bob, 'bans', 'carol'))));
await t('막힌 회원도 공감은 → 됨', assertSucceeds(updateDoc(doc(carol, 'reviews', rid('bob', day, '8')), { likes: arrayUnion('carol'), lc: increment(1) })));
await t('관리자 막기 풀기 → 됨', assertSucceeds(deleteDoc(doc(admin, 'bans', 'carol'))));
await t('풀린 뒤 후기 쓰기 → 됨', assertSucceeds(setDoc(doc(carol, 'reviews', rid('carol', day, '21')), review('carol', { pid: '21' }))));
await t('내 계정 문서에 차단 목록 → 됨', assertSucceeds(setDoc(doc(bob, 'users', 'bob'), { blocked: { carol: '콕플러' } }, { merge: true })));
await t('관리자 아닌데 설정 쓰기 → 막힘', assertFails(setDoc(doc(alice, 'config', 'home'), { order: [] })));
await t('내 계정 문서 → 됨', assertSucceeds(setDoc(doc(alice, 'users', 'alice'), { nick: '콕플러' })));
await t('남의 계정 문서 → 막힘', assertFails(getDoc(doc(bob, 'users', 'alice'))));

const rv = doc(nobody, 'regionViews', '서울_마포구');
await t('지역 세기 처음 (비회원) → 됨', assertSucceeds(setDoc(rv, { n: 1, sido: '서울', city: '마포구', at: serverTimestamp() })));
await t('지역 세기 1 올리기 → 됨', assertSucceeds(updateDoc(rv, { n: increment(1), at: serverTimestamp() })));
await t('지역 세기 한 번에 10 → 막힘', assertFails(updateDoc(rv, { n: increment(10), at: serverTimestamp() })));
await t('지역 세기 이름 바꾸기 → 막힘', assertFails(updateDoc(rv, { n: increment(1), city: '강남구', at: serverTimestamp() })));
await t('지역 세기 이름과 문서 다름 → 막힘', assertFails(setDoc(doc(nobody, 'regionViews', '서울_강남구'), { n: 1, sido: '서울', city: '마포구', at: serverTimestamp() })));
await t('지역 세기 처음부터 100 → 막힘', assertFails(setDoc(doc(nobody, 'regionViews', '부산_해운대구'), { n: 100, sido: '부산', city: '해운대구', at: serverTimestamp() })));
await t('지역 세기 읽기 → 됨', assertSucceeds(getDoc(rv)));

await env.cleanup();
console.log(`\n시험 ${n}개 중 실패 ${bad}개`);
process.exit(bad ? 1 : 0);
