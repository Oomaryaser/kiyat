import {
  CanActivate,
  ExecutionContext,
  ForbiddenException,
  Injectable,
  UnauthorizedException,
} from "@nestjs/common";
import { ConfigService } from "@nestjs/config";
import { JwtService } from "@nestjs/jwt";
import { Request } from "express";
import { UserRole } from "../common/enums/transit.enums";

export interface AuthenticatedOperatorRequest extends Request {
  user: {
    sub: string;
    phone: string;
    role: string;
  };
}

@Injectable()
export class OperatorAuthGuard implements CanActivate {
  constructor(
    private readonly jwt: JwtService,
    private readonly config: ConfigService,
  ) {}

  async canActivate(context: ExecutionContext) {
    const request = context
      .switchToHttp()
      .getRequest<AuthenticatedOperatorRequest>();
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
      if (
        payload.role !== UserRole.Operator &&
        payload.role !== UserRole.Admin &&
        payload.role !== UserRole.Owner &&
        payload.role !== UserRole.Support
      ) {
        throw new ForbiddenException("Operator role required");
      }
      request.user = payload;
      return true;
    } catch (error) {
      if (error instanceof ForbiddenException) throw error;
      throw new UnauthorizedException("Invalid bearer token");
    }
  }
}
