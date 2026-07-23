import 'package:flutter/material.dart';

import '../../../shared/widgets/skeleton_box.dart';

/// 검색 로딩용 결과 카드 스켈레톤 3개.
/// _SearchPlaceTile 과 동형(사진 박스 + 라벨/타이틀/지역 줄)으로 전환 호흡을 맞춘다.
/// 최근/인기/모의 장소는 만들지 않는다 — 오류 없이 데이터가 오면 실제 결과로 교체된다.
class SearchResultsSkeleton extends StatelessWidget {
  const SearchResultsSkeleton({super.key, this.count = 3});

  final int count;

  @override
  Widget build(BuildContext context) {
    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
      itemCount: count,
      separatorBuilder: (BuildContext context, int index) =>
          const SizedBox(height: 12),
      itemBuilder: (BuildContext context, int index) =>
          const _SearchPlaceSkeleton(),
    );
  }
}

class _SearchPlaceSkeleton extends StatelessWidget {
  const _SearchPlaceSkeleton();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                const SkeletonBox(height: 14, width: 84), // 카테고리 배지 자리
                const SizedBox(height: 10),
                const SkeletonBox(height: 16), // 타이틀 1줄
                const SizedBox(height: 6),
                const SkeletonBox(height: 16, width: 190), // 타이틀 2줄
                const SizedBox(height: 8),
                Row(
                  children: <Widget>[
                    const SkeletonBox(height: 12, width: 12, radius: 6),
                    const SizedBox(width: 6),
                    SkeletonBox(height: 12, width: 110, radius: 6), // 지역 자리
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          const SkeletonBox(width: 72, height: 72, radius: 12), // 사진 자리
        ],
      ),
    );
  }
}
