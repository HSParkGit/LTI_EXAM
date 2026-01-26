# frozen_string_literal: true

# 출결 관리 컨트롤러
# LTI Launch 후 ?tool=attendance로 접근
#
# Canvas 설정:
#   - Target Link URI: https://your-tool.com/lti/launch?tool=attendance
class AttendanceController < ApplicationController
  before_action :load_lti_claims
  before_action :set_lti_context

  # 출결 목록
  def index
    @user_role = determine_course_user_role
    @course_title = @lti_context.context_title
  end

  # 출결 상세
  def show
  end

  # 출결 생성 폼 (교수용)
  def new
  end

  # 출결 생성 (교수용)
  def create
  end

  # 출결 수정 폼 (교수용)
  def edit
  end

  # 출결 수정 (교수용)
  def update
  end

  # 출결 삭제 (교수용)
  def destroy
  end

  private

  # LTI Claims 로드 (세션에서)
  def load_lti_claims
    @lti_claims = session[:lti_claims]

    if @lti_claims.blank? || session[:lti_claims_expires_at] < Time.current
      flash[:error] = '세션이 만료되었습니다. Canvas에서 LTI Tool을 다시 실행해주세요.'
      redirect_to admin_lti_platforms_path
      return
    end
  end

  # LtiContext 설정
  def set_lti_context
    @lti_context = LtiContext.find(session[:lti_context_id])
  rescue ActiveRecord::RecordNotFound
    flash[:error] = '코스 정보를 찾을 수 없습니다.'
    redirect_to admin_lti_platforms_path
  end

  # 해당 코스에서의 사용자 역할 확인
  def determine_course_user_role
    raw_user_role = @lti_claims[:user_role] || @lti_claims["user_role"]

    if raw_user_role.present?
      case raw_user_role.to_s.downcase
      when 'instructor', 'teacher', 'administrator'
        return :instructor
      when 'student', 'learner'
        return :student
      end
    end

    user_roles = @lti_claims[:user_roles] || @lti_claims["user_roles"] || []
    if user_roles.any? { |role| role.to_s =~ /Instructor|Teacher|Administrator/i }
      return :instructor
    end

    :student
  end
end
