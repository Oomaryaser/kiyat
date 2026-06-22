import { Injectable, UnauthorizedException, Inject } from "@nestjs/common";
import { ConfigService } from "@nestjs/config";
import { JwtService } from "@nestjs/jwt";
import Redis from "ioredis";
import { UsersService } from "../users/users.service";

@Injectable()
export class AuthService {
  constructor(
    private readonly users: UsersService,
    private readonly jwt: JwtService,
    private readonly config: ConfigService,
    @Inject("REDIS_CLIENT") private readonly redis: Redis,
  ) {}

  async sendOtp(phone: string) {
    const otp = "123456";
    await this.redis.set(`otp:${phone}`, otp, "EX", 300);
    console.log(`[OTP stub] ${phone}: ${otp}`);
    return { message: "OTP sent" };
  }

  async verifyOtp(phone: string, otp: string) {
    const expected = await this.redis.get(`otp:${phone}`);
    if (expected !== otp) throw new UnauthorizedException("Invalid OTP");
    const user = await this.users.findOrCreatePassenger(phone);
    await this.redis.del(`otp:${phone}`);
    return this.signPair(user.id, user.phone, user.role);
  }

  async verifyDriverOtp(phone: string, otp: string) {
    const expected = await this.redis.get(`otp:${phone}`);
    if (expected !== otp) throw new UnauthorizedException("Invalid OTP");
    const user = await this.users.findOrCreateOperator(phone);
    await this.redis.del(`otp:${phone}`);
    return this.signPair(user.id, user.phone, user.role);
  }

  async refresh(refreshToken: string) {
    try {
      const payload = await this.jwt.verifyAsync<{
        sub: string;
        phone: string;
        role: string;
      }>(refreshToken, {
        secret: this.config.getOrThrow<string>("JWT_REFRESH_SECRET"),
      });
      return this.signPair(payload.sub, payload.phone, payload.role);
    } catch {
      throw new UnauthorizedException("Invalid refresh token");
    }
  }

  private async signPair(sub: string, phone: string, role: string) {
    const payload = { sub, phone, role };
    return {
      accessToken: await this.jwt.signAsync(payload, {
        secret: this.config.getOrThrow<string>("JWT_SECRET"),
        expiresIn: "15m",
      }),
      refreshToken: await this.jwt.signAsync(payload, {
        secret: this.config.getOrThrow<string>("JWT_REFRESH_SECRET"),
        expiresIn: "30d",
      }),
    };
  }
}
