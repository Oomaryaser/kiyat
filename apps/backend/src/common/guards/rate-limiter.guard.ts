import {
  CanActivate,
  ExecutionContext,
  Injectable,
  HttpException,
  HttpStatus,
} from "@nestjs/common";
import Redis from "ioredis";
import { ConfigService } from "@nestjs/config";

@Injectable()
export class PassengerWaitRateLimiterGuard implements CanActivate {
  private readonly redis: Redis;

  constructor(private readonly config: ConfigService) {
    this.redis = new Redis(
      this.config.get<string>("REDIS_URL", "redis://localhost:6379"),
    );
  }

  async canActivate(context: ExecutionContext): Promise<boolean> {
    const request = context.switchToHttp().getRequest();
    const ip = request.ip || request.connection?.remoteAddress || "unknown-ip";
    const body = request.body;
    const sessionId = body?.anonymousSessionId || ip;

    const key = `rate:wait:${sessionId}`;
    const limit = 10; // Max 10 requests per minute
    const ttl = 60; // 1 minute window

    try {
      const count = await this.redis.incr(key);
      if (count === 1) {
        await this.redis.expire(key, ttl);
      }

      if (count > limit) {
        throw new HttpException(
          "Too many requests from this session. Please try again later.",
          HttpStatus.TOO_MANY_REQUESTS,
        );
      }
    } catch (error) {
      if (error instanceof HttpException) throw error;
      // If Redis fails, fail open but log it, or we can choose to proceed. Let's just log and proceed so we don't break the app if Redis goes down temporarily.
      console.error("Rate limiter guard Redis error:", error);
    }

    return true;
  }
}

@Injectable()
export class SendOtpRateLimiterGuard implements CanActivate {
  private readonly redis: Redis;

  constructor(private readonly config: ConfigService) {
    this.redis = new Redis(
      this.config.get<string>("REDIS_URL", "redis://localhost:6379"),
    );
  }

  async canActivate(context: ExecutionContext): Promise<boolean> {
    const request = context.switchToHttp().getRequest();
    const phone = request.body?.phone;
    if (!phone) {
      return true;
    }

    const key = `rate:otp:${phone}`;
    const limit = 5; // Max 5 requests
    const ttl = 600; // 10 minutes (600 seconds)

    try {
      const count = await this.redis.incr(key);
      if (count === 1) {
        await this.redis.expire(key, ttl);
      }

      if (count > limit) {
        throw new HttpException(
          "Too many OTP requests. Please try again after 10 minutes.",
          HttpStatus.TOO_MANY_REQUESTS,
        );
      }
    } catch (error) {
      if (error instanceof HttpException) throw error;
      console.error("OTP Rate limiter guard Redis error:", error);
    }

    return true;
  }
}

