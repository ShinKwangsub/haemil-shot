#!/bin/sh
# 개발용: 증명 관문을 지나 shot 실행 파일(이 맥 아키텍처)을 만든다. 검사(test/verify.py)가 이 파일을 쓴다.
# 배포용 앱 번들(Haemil Shot.app, 두 아키텍처, 서명)은 dist/build.sh, DMG 는 dist/release.sh.
set -e
cd "$(dirname "$0")"
if ! ~/.bend/bin/bend PROOF.bend 2>&1 | grep -q "ALL PROOFS CHECK"; then
  echo "빌드 중단: bend PROOF.bend 가 ALL PROOFS CHECK 가 아닙니다" >&2
  exit 1
fi
~/.bend/bin/bend shot.bend -o shot
echo "빌드 완료: $(pwd)/shot"
