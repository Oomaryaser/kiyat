import { Body, Controller, Post, UseGuards } from "@nestjs/common";
import { ApiTags } from "@nestjs/swagger";
import { RefreshDto, SendOtpDto, VerifyOtpDto } from "./auth.dto";
import { AuthService } from "./auth.service";
import { SendOtpRateLimiterGuard } from "../common/guards/rate-limiter.guard";

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

  @Post("refresh")
  refresh(@Body() dto: RefreshDto) {
    return this.auth.refresh(dto.refreshToken);
  }
}
