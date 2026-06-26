import { Injectable, UnauthorizedException, ForbiddenException, NotFoundException, Inject } from "@nestjs/common";
import { ConfigService } from "@nestjs/config";
import { JwtService } from "@nestjs/jwt";
import Redis from "ioredis";
import { UsersService } from "../users/users.service";
import { UserRole } from "../common/enums/transit.enums";

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

  async sendOperatorOtp(phone: string) {
    const user = await this.users.findByPhone(phone);
    if (!user) {
      throw new NotFoundException("Access Denied: Not registered as an operator");
    }
    if (
      user.role !== UserRole.Operator &&
      user.role !== UserRole.Admin &&
      user.role !== UserRole.Owner &&
      user.role !== UserRole.Support
    ) {
      throw new ForbiddenException("Access Denied: Operator privileges required");
    }

    const otp = "123456";
    await this.redis.set(`otp:operator:${phone}`, otp, "EX", 300); // 5 min TTL
    await this.redis.del(`otp:attempts:operator:${phone}`); // Reset attempts
    console.log(`[Operator OTP stub] ${phone}: ${otp}`);
    return { message: "Operator OTP sent" };
  }

  async verifyOperatorOtp(phone: string, otp: string) {
    const user = await this.users.findByPhone(phone);
    if (!user) {
      throw new UnauthorizedException("Access Denied: User not found");
    }
    if (
      user.role !== UserRole.Operator &&
      user.role !== UserRole.Admin &&
      user.role !== UserRole.Owner &&
      user.role !== UserRole.Support
    ) {
      throw new ForbiddenException("Access Denied: Operator privileges required");
    }

    const attemptsKey = `otp:attempts:operator:${phone}`;
    const attemptsRaw = await this.redis.get(attemptsKey);
    const attempts = attemptsRaw ? parseInt(attemptsRaw, 10) : 0;
    if (attempts >= 5) {
      await this.redis.del(`otp:operator:${phone}`);
      throw new UnauthorizedException("Too many invalid attempts. Request a new OTP.");
    }

    const expected = await this.redis.get(`otp:operator:${phone}`);
    if (!expected || expected !== otp) {
      await this.redis.set(attemptsKey, (attempts + 1).toString(), "EX", 300);
      throw new UnauthorizedException("Invalid OTP");
    }

    await this.redis.del(`otp:operator:${phone}`);
    await this.redis.del(attemptsKey);
    return this.signPair(user.id, user.phone, user.role);
  }

  async getOperatorProfile(userId: string) {
    const user = await this.users.findById(userId);
    if (!user) throw new NotFoundException("Operator not found");
    return {
      id: user.id,
      phone: user.phone,
      role: user.role,
      nameAr: user.nameAr,
    };
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
