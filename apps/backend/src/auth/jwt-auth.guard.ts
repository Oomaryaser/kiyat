import {
  CanActivate,
  ExecutionContext,
  Injectable,
  UnauthorizedException,
} from "@nestjs/common";
import { ConfigService } from "@nestjs/config";
import { JwtService } from "@nestjs/jwt";
import { Request } from "express";

export interface AuthenticatedRequest extends Request {
  user: {
    sub: string;
    phone: string;
    role: string;
  };
}

@Injectable()
export class JwtAuthGuard implements CanActivate {
  constructor(
    private readonly jwt: JwtService,
    private readonly config: ConfigService,
  ) {}

  async canActivate(context: ExecutionContext) {
    const request = context.switchToHttp().getRequest<AuthenticatedRequest>();
    const header = request.headers.authorization;
    const [scheme, token] = header?.split(" ") ?? [];
    if (scheme !== "Bearer" || !token) {
      throw new UnauthorizedException("Missing bearer token");
    }

    try {
      const payload = await this.jwt.verifyAsync<{
        sub: string;
        phone: string;
        role: string;
      }>(token, {
        secret: this.config.getOrThrow<string>("JWT_SECRET"),
      });
      request.user = payload;
      return true;
    } catch {
      throw new UnauthorizedException("Invalid bearer token");
    }
  }
}
