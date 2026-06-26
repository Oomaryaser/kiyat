import { Body, Controller, Get, Post, Req, UseGuards } from "@nestjs/common";
import { ApiBearerAuth, ApiTags } from "@nestjs/swagger";
import { RefreshDto, SendOtpDto, VerifyOtpDto } from "./auth.dto";
import { AuthService } from "./auth.service";
import { SendOtpRateLimiterGuard } from "../common/guards/rate-limiter.guard";
import { OperatorAuthGuard, AuthenticatedOperatorRequest } from "./operator-auth.guard";

@ApiTags("auth")
@Controller("auth")
export class AuthController {
  constructor(private readonly auth: AuthService) {}

  @Post("send-otp")
  @UseGuards(SendOtpRateLimiterGuard)
  sendOtp(@Body() dto: SendOtpDto) {
    return this.auth.sendOtp(dto.phone);
  }

  @Post("verify-otp")
  verifyOtp(@Body() dto: VerifyOtpDto) {
    return this.auth.verifyOtp(dto.phone, dto.otp);
  }

  @Post("driver/verify-otp")
  verifyDriverOtp(@Body() dto: VerifyOtpDto) {
    return this.auth.verifyDriverOtp(dto.phone, dto.otp);
  }

  @Post("operator/login")
  @UseGuards(SendOtpRateLimiterGuard)
  sendOperatorOtp(@Body() dto: SendOtpDto) {
    return this.auth.sendOperatorOtp(dto.phone);
  }

  @Post("operator/verify-otp")
  verifyOperatorOtp(@Body() dto: VerifyOtpDto) {
    return this.auth.verifyOperatorOtp(dto.phone, dto.otp);
  }

  @Get("operator/me")
  @UseGuards(OperatorAuthGuard)
  @ApiBearerAuth()
  getOperatorMe(@Req() req: AuthenticatedOperatorRequest) {
    return this.auth.getOperatorProfile(req.user.sub);
  }

  @Post("refresh")
  refresh(@Body() dto: RefreshDto) {
    return this.auth.refresh(dto.refreshToken);
  }
}
