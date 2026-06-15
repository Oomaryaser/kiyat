import { Injectable } from "@nestjs/common";
import { InjectRepository } from "@nestjs/typeorm";
import { Repository } from "typeorm";
import { UserRole } from "../common/enums/transit.enums";
import { User } from "./user.entity";

@Injectable()
export class UsersService {
  constructor(
    @InjectRepository(User) private readonly users: Repository<User>,
  ) {}

  findByPhone(phone: string) {
    return this.users.findOne({ where: { phone } });
  }

  findById(id: string) {
    return this.users.findOne({ where: { id } });
  }

  async findOrCreatePassenger(phone: string) {
    const existing = await this.findByPhone(phone);
    if (existing) return existing;
    return this.users.save(
      this.users.create({ phone, role: UserRole.Passenger }),
    );
  }

  async findOrCreateOperator(phone: string) {
    const existing = await this.findByPhone(phone);
    if (existing) {
      if (existing.role === UserRole.Passenger) {
        existing.role = UserRole.Operator;
        return this.users.save(existing);
      }
      return existing;
    }
    return this.users.save(
      this.users.create({ phone, role: UserRole.Operator }),
    );
  }
}
