# Azure Dev Deployment — 과거 경로 종료

이전 `dev` 테넌트의 자동 배포 절차는 현재 실행 기준이 아니다.
`.github/workflows/azure-dev-deploy.yml`은 수동 안내만 남기며 클라우드 로그인·생성·배포를 하지 않는다.
과거 리소스가 지금도 존재하거나 복구 대상으로 사용 가능하다고 가정하지 않는다.

새 환경은 [Azure 관리형 이관 준비](azure-managed-prepayment-readiness.md)와
[Azure 운영 비밀 계약](azure-runtime-secret-candidate.md)을 따른다.

- 결제·대상 구독·예산 확인 후 별도 승인으로 인프라를 생성한다.
- staging/prod의 관리 ID·OIDC·DB·인증을 확인한다.
- 검토한 SHA와 이미지 digest를 수동 배포하고 실환경에서 검증한다.
- 운영 전환과 DNS 변경은 그 다음 별도 단계다.

과거 실행 기록은 Git 이력에 남아 있다. 이전 성공 기록을 새 환경의 검증 증거로 재사용하지 않는다.
