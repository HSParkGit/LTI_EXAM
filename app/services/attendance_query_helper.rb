# frozen_string_literal: true

#
# 출결 데이터 조회 헬퍼
# Canvas 원본 QueryHelper 포팅
#
# 핵심 기능:
# - 학생 식별자 변환 (LTI Claims → Panopto/Zoom 식별자)
# - 출결 레코드 조회 (content_tag_id 기반)
# - 레코드 인덱싱 (빠른 조회용)
#
class AttendanceQueryHelper
  class << self
    # ========================================
    # 학생 식별자 변환
    # ========================================

    # LTI Claims에서 학생 식별자 추출
    # Panopto: custom_canvas_user_login_id (unique_id)
    # Zoom: email
    #
    # @param lti_claims [Hash] LTI Claims (HashWithIndifferentAccess 권장)
    # @param session [AttendanceSession] 세션
    # @return [String, nil] 학생 식별자
    def extract_student_identifier(lti_claims, session)
      if session.vod?
        # Panopto: Canvas login_id (unique_id)
        # 우선순위: custom_canvas_user_login_id > login_id > user_name
        lti_claims[:custom_canvas_user_login_id] ||
          lti_claims['custom_canvas_user_login_id'] ||
          lti_claims[:login_id] ||
          lti_claims['login_id'] ||
          lti_claims[:user_name] ||
          lti_claims['user_name']
      else
        # Zoom: email
        # 우선순위: email > user_email
        lti_claims[:email] ||
          lti_claims['email'] ||
          lti_claims[:user_email] ||
          lti_claims['user_email']
      end
    end

    # 여러 세션에 대한 학생 식별자 맵 생성
    #
    # @param lti_claims [Hash] LTI Claims (HashWithIndifferentAccess 권장)
    # @param sessions [Array<AttendanceSession>] 세션 배열
    # @return [Hash] { session_id => identifier }
    def build_identifiers_map(lti_claims, sessions)
      has_vod = sessions.any?(&:vod?)
      has_live = sessions.any?(&:live?)

      vod_id = if has_vod
                 lti_claims[:custom_canvas_user_login_id] ||
                   lti_claims['custom_canvas_user_login_id'] ||
                   lti_claims[:login_id] ||
                   lti_claims['login_id'] ||
                   lti_claims[:user_name] ||
                   lti_claims['user_name']
               end

      live_id = if has_live
                  lti_claims[:email] ||
                    lti_claims['email'] ||
                    lti_claims[:user_email] ||
                    lti_claims['user_email']
                end

      sessions.each_with_object({}) do |session, map|
        identifier = session.vod? ? vod_id : live_id
        map[session.id] = identifier if identifier.present?
      end
    end

    # ========================================
    # 레코드 조회
    # ========================================

    # 여러 세션의 출결 레코드 일괄 조회
    #
    # @param sessions [Array<AttendanceSession>] 세션 배열
    # @return [Array] 출결 레코드 배열
    def fetch_records_for_sessions(sessions)
      return [] if sessions.blank?

      content_tag_ids = sessions.map(&:content_tag_id).compact
      return [] if content_tag_ids.blank?

      vod_sessions = sessions.select(&:vod?)
      live_sessions = sessions.select(&:live?)

      results = []

      if vod_sessions.any?
        vod_tag_ids = vod_sessions.map(&:content_tag_id).compact
        results.concat(
          PanoptoViewResult.by_content_tags(vod_tag_ids).priority_ordered.to_a
        )
      end

      if live_sessions.any?
        live_tag_ids = live_sessions.map(&:content_tag_id).compact
        results.concat(
          ZoomViewResult.by_content_tags(live_tag_ids).priority_ordered.to_a
        )
      end

      results
    end

    # 레코드 인덱싱 (빠른 조회용)
    # [content_tag_id, student_id] => [records]
    #
    # @param records [Array] 출결 레코드 배열
    # @return [Hash] 인덱스 해시
    def index_records(records)
      records.group_by { |r| [r.content_tag_id, r.student_id] }
    end

    # 인덱스에서 특정 학생의 레코드 조회
    #
    # @param identifier [String] 학생 식별자
    # @param records_index [Hash] 인덱스 해시
    # @param content_tag_id [Integer] content_tag_id
    # @return [Object, nil] 출결 레코드
    def find_record(identifier, records_index, content_tag_id)
      return nil unless identifier.present?

      records_index[[content_tag_id, identifier]]&.first
    end

    # ========================================
    # 학생별 출결 조회
    # ========================================

    # 특정 학생의 모든 세션 출결 조회
    #
    # @param sessions [Array<AttendanceSession>] 세션 배열
    # @param lti_claims [Hash] LTI Claims
    # @return [Hash] { session_id => record }
    def fetch_student_records(sessions, lti_claims)
      return {} if sessions.blank?

      identifiers_map = build_identifiers_map(lti_claims, sessions)
      records = fetch_records_for_sessions(sessions)
      records_index = index_records(records)

      sessions.each_with_object({}) do |session, result|
        identifier = identifiers_map[session.id]
        next unless identifier && session.content_tag_id

        record = find_record(identifier, records_index, session.content_tag_id)
        result[session.id] = record if record
      end
    end
  end
end
