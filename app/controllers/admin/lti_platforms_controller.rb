# frozen_string_literal: true

module Admin
  # LTI Platform 관리 컨트롤러
  # Canvas 인스턴스(iss)와 Client ID를 등록/수정/삭제
  #
  # 보안 고려사항:
  #   - 프로덕션에서는 인증/권한 체크 추가 필요
  #   - 예: before_action :authenticate_admin!
  class LtiPlatformsController < ApplicationController
    before_action :set_lti_platform, only: [:edit, :update, :destroy]
    
    # Platform 목록
    def index
      @lti_platforms = LtiPlatform.order(created_at: :desc)
    end

    # 새 Platform 등록 폼
    def new
      @lti_platform = LtiPlatform.new
    end

    # Platform 생성
    def create
      @lti_platform = LtiPlatform.new(lti_platform_params)
      
      if @lti_platform.save
        # 캐시 무효화
        Lti::PlatformConfig.clear_cache(@lti_platform.iss)
        
        redirect_to admin_lti_platforms_path, notice: "Canvas Platform이 등록되었습니다."
      else
        render :new, status: :unprocessable_entity
      end
    end

    # Platform 수정 폼
    def edit
    end

    # Platform 수정
    def update
      params_hash = lti_platform_params
      # Client Secret이 비어있으면 기존 값 유지
      if params_hash[:client_secret].blank?
        params_hash.delete(:client_secret)
      end
      # Canvas API Token이 비어있으면 기존 값 유지
      if params_hash[:canvas_api_token].blank?
        params_hash.delete(:canvas_api_token)
      end
      
      if @lti_platform.update(params_hash)
        # 캐시 무효화
        Lti::PlatformConfig.clear_cache(@lti_platform.iss)
        
        redirect_to admin_lti_platforms_path, notice: "Canvas Platform이 수정되었습니다."
      else
        render :edit, status: :unprocessable_entity
      end
    end

    # Platform 삭제
    def destroy
      iss = @lti_platform.iss
      @lti_platform.destroy
      
      # 캐시 무효화
      Lti::PlatformConfig.clear_cache(iss)
      
      redirect_to admin_lti_platforms_path, notice: "Canvas Platform이 삭제되었습니다."
    end

    private

    def set_lti_platform
      @lti_platform = LtiPlatform.find(params[:id])
    end

    def lti_platform_params
      params.require(:lti_platform).permit(:iss, :client_id, :client_secret, :canvas_api_token, :canvas_url, :name, :active)
    end
  end
end
